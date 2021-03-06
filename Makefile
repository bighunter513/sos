CROSS_PATH = /Users/sonald/crossgcc/bin
CXX = $(CROSS_PATH)/i686-elf-g++
CPP = $(CROSS_PATH)/i686-elf-cpp
CC = $(CROSS_PATH)/i686-elf-gcc
CXXFLAGS = -std=c++11 -g -I./include -ffreestanding  \
		 -O2 -Wall -Wextra -fno-exceptions -fno-rtti -DDEBUG -fno-strict-aliasing -D__sos__ -D_SOS_KERNEL_
DISKIMG=hd.img

USER_FLAGS = -std=c++11 -I./include -I./user/libc -ffreestanding  \
	   -O2 -Wall -Wextra -fno-exceptions -fno-rtti -DDEBUG

OBJS_DIR = objs

crtbegin_o=$(shell $(CXX) $(CXXFLAGS) -print-file-name=crtbegin.o)
crtend_o=$(shell $(CXX) $(CXXFLAGS) -print-file-name=crtend.o)

kernel_srcs = kern/boot.s kern/core/irq_stubs.s kern/core/context.s \
	$(wildcard kern/*.cc) \
	$(wildcard kern/runtime/*.cc) \
	$(wildcard kern/core/*.cc) \
	$(wildcard kern/drv/*.cc) \
	$(wildcard kern/utils/*.cc) \
	$(wildcard lib/*.cc)

kernel_objs := $(patsubst %.cc, $(OBJS_DIR)/%.o, $(kernel_srcs))
kernel_objs := $(patsubst %.s, $(OBJS_DIR)/%.o, $(kernel_objs))

kern_objs := $(OBJS_DIR)/kern/runtime/crti.o $(crtbegin_o) \
	$(kernel_objs) \
	$(crtend_o) $(OBJS_DIR)/kern/runtime/crtn.o

DEPFILES := $(patsubst %.cc, $(OBJS_DIR)/%.d, $(kernel_srcs))
DEPFILES := $(patsubst %.s, $(OBJS_DIR)/%.d, $(DEPFILES))

ulib_src = $(wildcard lib/*.cc) $(wildcard user/libc/*.c)
ulib_obj := $(patsubst lib/%.cc, $(OBJS_DIR)/user/lib/%.o, $(ulib_src)) $(OBJS_DIR)/user/lib/cxx_rt.o
ulib_obj := $(patsubst user/libc/%.c, $(OBJS_DIR)/user/lib/%.o, $(ulib_obj))

DEPFILES := $(DEPFILES) $(patsubst %.o, %.d, $(ulib_obj))

ulib_pre_objs := $(OBJS_DIR)/user/lib/crti.o $(crtbegin_o) 
ulib_post_objs := $(ulib_obj) $(crtend_o) $(OBJS_DIR)/user/lib/crtn.o

uprogs_objs = $(patsubst user/%.c, $(OBJS_DIR)/user/bin/%.o, \
			  $(wildcard user/*.c))
uprogs = $(patsubst $(OBJS_DIR)/user/bin/%.o, bin/%, $(uprogs_objs))

all: run ramfs_gen

# for debugging
print-%: ; @echo $* = $($*)

-include $(DEPFILES)

$(OBJS_DIR)/kern/%.d: kern/%.cc
	@mkdir -p $(@D)
	$(CPP) $(CXXFLAGS) $< -MM -MT $(@:.d=.o) >$@

$(OBJS_DIR)/lib/%.d: lib/%.cc
	@mkdir -p $(@D)
	$(CPP) $(CXXFLAGS) $< -MM -MT $(@:.d=.o) >$@

# for userspace
$(OBJS_DIR)/user/lib/cxx_rt.d: kern/runtime/cxx_rt.cc
	@mkdir -p $(@D)
	$(CPP) $(USER_FLAGS) $< -MM -MT $(@:.d=.o) >$@

$(OBJS_DIR)/user/lib/%.d: user/libc/%.c
	@mkdir -p $(@D)
	$(CPP) $(USER_FLAGS) $< -MM -MT $(@:.d=.o) >$@

$(OBJS_DIR)/user/bin/%.d: user/%.c
	@mkdir -p $(@D)
	$(CPP) $(USER_FLAGS) $< -MM -MT $(@:.d=.o) >$@

# print makefile variable (for debug purpose)
print-%: ; @echo $* = $($*)

debug: kernel
	qemu-system-i386 -kernel kernel -initrd initramfs.img -m 64 -s -monitor stdio \
	-drive file=$(DISKIMG),format=raw -vga vmware

run: kernel $(DISKIMG) initramfs.img
	qemu-system-i386 -m 64 -s -monitor stdio -drive file=$(DISKIMG),format=raw -vga vmware

$(DISKIMG): kernel $(uprogs) initramfs.img logo.ppm
	hdiutil attach $(DISKIMG)
	cp grub.cfg /Volumes/SOS/boot/grub/
	cp kernel /Volumes/SOS
	cp logo.ppm /Volumes/SOS
	cp bin/init /Volumes/SOS
	@mkdir -p /Volumes/SOS/bin
	cp bin/* /Volumes/SOS/bin
	cp initramfs.img /Volumes/SOS
	#hdiutil detach disk2

kernel: $(kern_objs) kern/kernel.ld
	$(CXX) -T kern/kernel.ld -O2 -nostdlib -o $@ $^ -lgcc

$(OBJS_DIR)/kern/%.o: kern/%.cc
	@mkdir -p $(@D)
	$(CXX) $(CXXFLAGS) -c -o $@ $<

$(OBJS_DIR)/kern/%.o: kern/%.s
	@mkdir -p $(@D)
	nasm -f elf32 -o $@ $<

$(OBJS_DIR)/lib/%.o: lib/%.cc
	@mkdir -p $(@D)
	$(CXX) $(CXXFLAGS) -c -o $@ $<

# tools
ramfs_gen: tools/ramfs_gen.c
	gcc -o $@ $^


#################################################################
# user space 
#################################################################

$(OBJS_DIR)/user/lib/cxx_rt.o: kern/runtime/cxx_rt.cc
	@mkdir -p $(@D)
	$(CXX) $(USER_FLAGS) -c -o $@ $<

$(OBJS_DIR)/user/lib/%.o: kern/runtime/%.s
	@mkdir -p $(@D)
	nasm -f elf32 -o $@ $<

$(OBJS_DIR)/user/lib/%.o: lib/%.cc
	@mkdir -p $(@D)
	$(CXX) $(USER_FLAGS) -c -o $@ $<

$(OBJS_DIR)/user/lib/%.o: user/libc/%.c
	@mkdir -p $(@D)
	$(CXX) $(USER_FLAGS) -c -o $@ $<

$(OBJS_DIR)/user/bin/%.o: user/%.c
	@mkdir -p $(@D)
	$(CXX) $(USER_FLAGS) -c -o $@ $<

bin/%: $(ulib_pre_objs) $(OBJS_DIR)/user/bin/%.o $(ulib_post_objs) user/user.ld
	@mkdir -p $(@D)
	$(CXX) $(USER_FLAGS) -T user/user.ld -nostdlib -o $@ $^


initramfs.img: bin/echo ramfs_gen
	./ramfs_gen README.md user/echo.c bin/echo

.PHONY: clean

clean:
	-rm $(OBJS_DIR)/kern/*.o
	-rm $(OBJS_DIR)/lib/*.o
	-rm $(OBJS_DIR)/kern/core/*.o
	-rm $(OBJS_DIR)/kern/runtime/*.o
	-rm $(OBJS_DIR)/kern/utils/*.o
	-rm $(OBJS_DIR)/kern/drv/*.o
	-rm $(OBJS_DIR)/user/lib/*.o
	-rm $(OBJS_DIR)/user/bin/*.o
	-rm $(OBJS_DIR)/kern/*.d
	-rm $(OBJS_DIR)/lib/*.d
	-rm $(OBJS_DIR)/kern/core/*.d
	-rm $(OBJS_DIR)/kern/runtime/*.d
	-rm $(OBJS_DIR)/kern/utils/*.d
	-rm $(OBJS_DIR)/kern/drv/*.d
	-rm $(OBJS_DIR)/user/lib/*.d
	-rm $(OBJS_DIR)/user/bin/*.d
	-rm bin/*
	-rm kernel
