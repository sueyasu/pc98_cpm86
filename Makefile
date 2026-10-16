BUILD_DIR := build

NASM ?= nasm
PYTHON ?= python3
HXCFE ?= hxcfe

CPM86_CORE ?= external/system/cpm86_core.bin
EXTERNAL_COMMANDS := $(wildcard external/commands/*.CMD external/commands/*.cmd)

FDIPL := $(BUILD_DIR)/fdipl.bin
CBIOS := $(BUILD_DIR)/cbios.bin
RESIDENT := $(BUILD_DIR)/resident.bin
SYSTEM := $(BUILD_DIR)/system.bin

IMG_2DD := $(BUILD_DIR)/pc98_cpm86_2dd.img
IMG_2HD := $(BUILD_DIR)/pc98_cpm86_2hd.img
D88_2DD := $(BUILD_DIR)/pc98_cpm86_2dd.d88
D88_2HD := $(BUILD_DIR)/pc98_cpm86_2hd.d88
HFE_2DD := $(BUILD_DIR)/pc98_cpm86_2dd.hfe
HFE_2HD := $(BUILD_DIR)/pc98_cpm86_2hd.hfe

.PHONY: all raw d88 hfe clean check-tools check-core check-hxcfe

all: raw d88

raw: $(IMG_2DD) $(IMG_2HD)

d88: $(D88_2DD) $(D88_2HD)

hfe: $(HFE_2DD) $(HFE_2HD)

check-tools:
	@set -e; \
	for t in $(NASM) $(PYTHON); do \
		command -v $$t >/dev/null 2>&1 || { echo "missing required tool: $$t" >&2; exit 1; }; \
	done

check-core:
	@test -f "$(CPM86_CORE)" || { \
		echo "missing CP/M-86 CCP/BDOS core: $(CPM86_CORE)" >&2; \
		echo "see BUILD.md for the required 0x2500-byte core file" >&2; \
		exit 1; \
	}
	@test "$$(stat -c%s "$(CPM86_CORE)")" -eq 9472 || { \
		echo "$(CPM86_CORE): expected 9472 (0x2500) bytes" >&2; \
		exit 1; \
	}

check-hxcfe:
	@command -v $(HXCFE) >/dev/null 2>&1 || { \
		echo "missing optional HxC command-line converter: $(HXCFE)" >&2; \
		echo "RAW and D88 images are available with 'make' even without HxC." >&2; \
		exit 1; \
	}

$(BUILD_DIR):
	mkdir -p $@

$(FDIPL): src/fdipl.asm | $(BUILD_DIR)
	$(NASM) -f bin $< -o $@
	@test "$$(stat -c%s $@)" -eq 512 || { echo "$@: expected 512 bytes" >&2; exit 1; }

$(CBIOS): src/cbios.asm | $(BUILD_DIR)
	$(NASM) -f bin $< -o $@
	@actual=$$(stat -c%s $@); \
	if [ "$$actual" -gt 6400 ]; then \
		echo "$@: assembled size $$actual exceeds 6400-byte BIOS area" >&2; \
		exit 1; \
	fi
	truncate -s 6400 $@

$(RESIDENT): $(CBIOS) | check-core $(BUILD_DIR)
	cat "$(CPM86_CORE)" $(CBIOS) > $@
	@test "$$(stat -c%s $@)" -eq 15872 || { echo "$@: expected 15872 bytes" >&2; exit 1; }

$(SYSTEM): $(FDIPL) $(RESIDENT)
	cat $^ > $@
	@test "$$(stat -c%s $@)" -eq 16384 || { echo "$@: expected 16384 bytes" >&2; exit 1; }

$(IMG_2DD): $(SYSTEM) $(EXTERNAL_COMMANDS) scripts/mkcpm86image.py | $(BUILD_DIR)
	$(PYTHON) scripts/mkcpm86image.py --format 2dd --system $(SYSTEM) \
		$(foreach f,$(EXTERNAL_COMMANDS),--file $(f)) $@

$(IMG_2HD): $(SYSTEM) $(EXTERNAL_COMMANDS) scripts/mkcpm86image.py | $(BUILD_DIR)
	$(PYTHON) scripts/mkcpm86image.py --format 2hd --system $(SYSTEM) \
		$(foreach f,$(EXTERNAL_COMMANDS),--file $(f)) $@

$(D88_2DD): $(IMG_2DD) scripts/raw2d88.py | $(BUILD_DIR)
	$(PYTHON) scripts/raw2d88.py --format 2dd --name "PC98 CPM86 2DD" $< $@

$(D88_2HD): $(IMG_2HD) scripts/raw2d88.py | $(BUILD_DIR)
	$(PYTHON) scripts/raw2d88.py --format 2hd --name "PC98 CPM86 2HD" $< $@

$(HFE_2DD): $(D88_2DD) | check-hxcfe
	$(HXCFE) -finput:"$<" -conv:HXC_HFE -foutput:"$@"

$(HFE_2HD): $(D88_2HD) | check-hxcfe
	$(HXCFE) -finput:"$<" -conv:HXC_HFE -foutput:"$@"

clean:
	rm -rf $(BUILD_DIR)
