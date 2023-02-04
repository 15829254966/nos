##############################################
# Copyright (C) 2023-2023 胡启航<Nick Hu>
#
# Author: 胡启航<Nick Hu>
#
# Email: huqihan@live.com
##############################################

VERSION = 1
PATCHLEVEL = 0
SUBLEVEL = 0

#打开显示选项
ifneq ($(V),1)
	Q := @
endif

ifneq ($(MV), 1)
	N := --no-print-directory
endif

ifndef $(ARCH)
    ARCH := arm
endif

dir-y := init
dir-y += arch
dir-y += drivers
dir-y += kernel
dir-y += libs
dir-y += modules
dir-y += board
dir-y += app

dir-run := $(dir-y:%=%-run)
ifndef $(out-dir)
    out-dir := out
endif
obj-dir := $(dir-y:%=$(out-dir)/%)
obj-all := $(dir-y:%=$(out-dir)/%/built-in.o)

#链接脚本
LDSCRIPT :=

-include $(out-dir)/.config
include scripts/Makefile.config
include arch/$(ARCH)/Makefile.config
ifneq ($(CONFIG_BOARD),)
board := $(shell echo $(CONFIG_BOARD) | sed 's/\"//g')
include board/$(board)/Makefile.config
endif

OOCD		:= openocd
OOCD_INTERFACE	:= flossjtag

LDSCRIPT_S := $(filter %.S,$(LDSCRIPT))
LDSCRIPT_S := $(LDSCRIPT_S:%.S=$(out-dir)/%)
LDSCRIPT_LD := $(filter-out %.S,$(LDSCRIPT))
LDSCRIPT_LD := $(LDSCRIPT_LD:%=$(out-dir)/%)
LDFLAGS += $(LDSCRIPT:%.S=-T$(out-dir)/%)

.PHONY: all flash debug clean %_config defconfig size stflash jflash

all:$(TARGET_LIST) $(TARGET_BIN) $(TARGET_HEX) $(TARGET_ELF) $(TARGET_IMG) size

size: $(TARGET_ELF)
	@echo "SIZE     $(<:$(out-dir)/%=%)"
	$(Q)$(SIZE) --format=berkeley $<
	@echo build done

$(TARGET_HEX): $(TARGET_ELF)
	@echo "OBJCOPY  $(@:$(out-dir)/%=%)"
	$(Q)$(OBJCOPY) $<  $@ -Oihex

$(TARGET_BIN): $(TARGET_ELF)
	@echo "OBJCOPY  $(@:$(out-dir)/%=%)"
	$(Q)$(OBJCOPY) $<  $@ -Obinary

$(TARGET_IMG): $(TARGET_BIN)
	@echo "CREATE   $(@:$(out-dir)/%=%)"
	$(Q)-$(RM) $@
	$(Q)$(PYTHON) scripts/create_img.py $< $(VERSION) $(PATCHLEVEL) $(SUBLEVEL) 1 $@

$(TARGET_LIST): $(TARGET_ELF)
	@echo "OBJDUMP  $(@:$(out-dir)/%=%)"
	$(Q)$(OBJDUMP) -S $< > $@
$(TARGET_ELF): $(obj-all) $(LDSCRIPT_S) $(LDSCRIPT_LD)
	@echo "LD       $(@:$(out-dir)/%=%)"
	$(Q)$(CC) $(LDFLAGS) -o $@ $(obj-all)

$(LDSCRIPT_LD): $(out-dir)/%:%
	@echo "CP       $(notdir $@)"
	$(Q)cp $< $@


$(LDSCRIPT_S): $(out-dir)/%:%.S
	@echo "E        $(notdir $@)"
	$(Q)$(CC) -E $(INC_DIR) $(DEFINES) -P -o $@ $<

$(obj-all): $(obj-dir) $(out-dir)/.config $(out-dir)/include/autocfg.h
	$(Q)$(MAKE) $(N) -f scripts/Makefile.build dir=$(@:$(out-dir)/%/$(notdir $@)=%) \
		out-dir=$(out-dir) Q=$(Q) N=$(N) ARCH=$(ARCH) \
		TARGET=$(notdir $@) built-in.o

$(obj-dir):$(out-dir)
	$(Q)if [ ! -d $@ ]; then \
		mkdir $@; \
	fi

$(out-dir):
	$(Q)if [ ! -d $@ ]; then \
		mkdir $@; \
	fi

# 使用OpenOCD下载hex程序
flash:
	@echo "OPEN_OCD FLASH $(TARGET_HEX:$(out-dir)/%=%)"
	$(Q)$(OOCD) $(OOCDFLAGS) -c "program $(TARGET_HEX) verify reset exit"

# 使用st-link下载bin程序
stflash:
	@echo "ST-FLASH     $(TARGET_BIN:$(out-dir)/%=%)"
	$(Q)st-flash write $(TARGET_BIN) 0x08000000

# 使用J-link下载hex程序
jflash:
	@echo "J-FLASH     $(TARGET_HEX:$(out-dir)/%=%)"
	$(Q)scripts/jflash.sh $(TARGET_HEX)

# 使用GDB 通过sdtin/out管道与OpenOCD连接 并在main函数处打断点后运行
debug:
	@echo "GDB DEBUG $(TARGET_ELF)"
	$(Q)$(GDB) -iex 'target extended | $(OOCD) $(OOCDFLAGS) -c "gdb_port pipe"' \
	-iex 'monitor reset halt' -ex 'load' -ex 'break nos_start' -ex 'c' $(TARGET_ELF)

debug-server:
	@echo "GDB DEBUG $(TARGET_ELF)"
	$(Q)$(OOCD) $(OOCDFLAGS) -c "gdb_port 1234"

%_config: $(obj-dir)
	@echo "write to .config"
	$(Q)$(PYTHON) scripts/config.py $(VERSION) $(PATCHLEVEL) $(SUBLEVEL) $(ARCH) arch/$(ARCH)/config/$@ $(out-dir)/.config
	$(Q)if [ ! -d $(out-dir)/include ]; then \
		mkdir $(out-dir)/include; \
	fi
	$(Q)$(PYTHON) scripts/autocfg.py $(out-dir)/.config $(out-dir)/include/autocfg.h
	$(Q)cp $(OOCDCFG) $(out-dir)/
	$(Q)cp $(SVD_CFG) $(out-dir)/board.svd

defconfig: $(obj-dir)
	@echo "write to .config"
	$(Q)$(PYTHON) scripts/config.py $(VERSION) $(PATCHLEVEL) $(SUBLEVEL) $(ARCH) arch/$(ARCH)/config/$@ $(out-dir)/.config
	$(Q)if [ ! -d $(out-dir)/include ]; then \
		mkdir $(out-dir)/include; \
	fi
	$(Q)$(PYTHON) scripts/autocfg.py $(out-dir)/.config $(out-dir)/include/autocfg.h
	$(Q)cp $(OOCDCFG) $(out-dir)/
	$(Q)cp $(SVD_CFG) $(out-dir)/board.svd

clean:
	$(Q)-$(RM) $(out-dir)
	@echo "clean done"
