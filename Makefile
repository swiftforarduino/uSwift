# This file creates the microswift standard library, runtime and related objects.
# The top level Makefile creates the "module" (the blob of precompiled headers)
# that is ingested by the swift compiler and shared across all architectures.
# Makefile.in creates the binary objects and static libraries. The intention is
# to upgrade that to spit out a separate version per AVR "architecture", and
# maybe equivalent on 32-bit ISAs.

# global settings
WHOLE_MODULE_OPT ?= yes
export MODULE_NAME ?= Swift
SWIFT_ONONE_DIR ?= SwiftOnoneSupport
SWIFT_ONONE_MODULE ?= SwiftOnoneSupport

# build components
ALL_SWIFT_SOURCES_SHARED = CoreOperators.swift CoreAliases.swift RawRepresentable.swift\
 LiteralProtocols.swift TopLevelFunctions.swift CoreProtocols.swift CoreFloatingPoint.swift CoreBinaryFloatingPoint.swift\
 Float.swift Float16.swift CoreFloatingPointFunctions.swift Optional.swift Bridging.swift\
 CoreNumericProtocols.swift BinaryInteger.swift CoreIntegers.swift ErrorType.swift Bool.swift Integers.swift\
 Ranges.swift Sequence.swift Stride.swift Slice.swift Collection.swift\
 BidirectionalCollection.swift RandomAccessCollection.swift ClosedRange.swift\
 MutableCollection.swift Hash.swift Pointer.swift UnsafeBufferPointer.swift\
 UnsafeRawBufferPointer.swift UnsafeRawPointer.swift Indices.swift\
 Existential.swift Algorithm.swift FixedWidth.swift IntegerMath.swift\
 CTypes.swift UnsafePointer.swift ObjectIdentifier.swift\
 CollectionAlgorithms.swift WriteBackMutableSlice.swift\
 Random.swift RangeReplaceableCollection.swift MemoryLayout.swift Tuple.swift\
 SequenceAlgorithms.swift LifetimeManager.swift Repeat.swift EmptyCollection.swift\
 CollectionOfOne.swift StringLiterals.swift StaticString.swift StringInterpolation.swift\
 ArrayType.swift ArrayBufferProtocol.swift ArrayLiterals.swift\
 ArrayShared.swift ContiguousArray.swift SliceBuffer.swift ArraySlice.swift Array.swift ArrayBody.swift\
 ArrayCast.swift AnyHashable.swift ManagedBuffer.swift Reverse.swift Map.swift\
 Zip.swift LazySequence.swift LazyCollection.swift Filter.swift FlatMap.swift Flatten.swift DropWhile.swift\
 Volatile.swift uSwift.swift Identifiable.swift OptionSet.swift Sendable.swift SetAlgebra.swift\
 Unmanaged.swift ContiguousArrayBuffer.swift\
 Unicode.swift UnicodeScalar.swift UnicodeEncoding.swift UTF8.swift UTF16.swift ValidUTF8Buffer.swift\
 UnicodeParser.swift UIntBuffer.swift UTFEncoding.swift UTF32.swift\
 Volatile-stdlib.swift TemporaryAllocation.swift\
 MutableRawSpan.swift MutableSpan.swift RawSpan.swift Span.swift\
 InlineArray.swift\
 ByteOrder.swift FullyInhabited.swift UniqueBox.swift\

# Bitset.swift

 # AVRArrayBuffer.swift
 # SwiftifyImport.swift\ - requires String
 # UnsafeBufferPointerSlice.swift\

# no longer using ContiguousArrayBuffer.swift 
# add runtime in Array.cpp or as little as needed

SHIMS_DIR = uSwiftShims

export BUILD_DIR = $(USWIFT_ARCH_BIN_PATH)

EXTRA_RUNTIME_INCLUDES = -Illvm-include -Illvm-swift-built-include

# build settings
SWIFT_EXTRA_OPTS = -Xfrontend -suppress-warnings -parse-as-library -parse-stdlib $(TARGET_OPTS) $(LLVM_DEBUG_OPTS)\
 -nostdimport -I $(SHIMS_DIR) $(ARCH_INCLUDES) $(ARCH_SWIFT_SYSTEM_INCLUDES) $(SWIFTC_ARCH_DEFINES) $(EXPERIMENTAL_FEATURE_FLAG)\
 -Xfrontend -disable-reflection-metadata -Xfrontend -disable-stack-protector

include Makefile.in

ifeq ($(ARCH),AVR)
ALL_SWIFT_SOURCES_ARCH_EXTRA = Progmem.swift
endif

ifeq ($(EXPERIMENTAL_FEATURE),Embedded)
$(info EMBEDDED)
# The embedded mini runtime
ALL_SWIFT_SOURCES_ARCH_EXPERIMENTS = EmbeddedRuntime.swift
endif

ifeq ($(ARCH_INT_BIT_WIDTH),16)
	ALL_SWIFT_SOURCES_ARCH = Integer-16.swift IntegerMath-16.swift CTypes-16.swift $(ALL_SWIFT_SOURCES_ARCH_EXTRA) $(ALL_SWIFT_SOURCES_ARCH_EXPERIMENTS)
else ifeq ($(ARCH_INT_BIT_WIDTH),32)
	ALL_SWIFT_SOURCES_ARCH = Integer-32.swift IntegerMath-32.swift CTypes-32.swift $(ALL_SWIFT_SOURCES_ARCH_EXTRA) $(ALL_SWIFT_SOURCES_ARCH_EXPERIMENTS)
else
	$(error "$(ARCH_INT_BIT_WIDTH) is not a supported integer bit width")
endif

ALL_SWIFT_SOURCES = $(ALL_SWIFT_SOURCES_SHARED) $(ALL_SWIFT_SOURCES_ARCH) $(VERSION_FILE)

VERSION_FILE = version.swift

# CORES = avr25 avr3 avr31 avr35 avr4 avr5 avr51 avr6

# start small with the cores we need, then add the rarer cores like avr25 avr3
CORES = avr5 avr6

# The "standard library" consists of a clang/swift module and object library
# effectively as equivalent to headers and static library in other products

# ** TARGETS **

# top level
all: $(BUILD_DIR) $(MODULE_NAME) cores

cores: $(CORES) | $(BUILD_DIR)

$(CORES):
	CORE=$@ MCU=$@ $(MAKE) -f Makefile.core.in

$(OUTPUT_MAP_FILE): $(ALL_SWIFT_SOURCES) | $(BUILD_DIR)
	@(echo "{";for i in $^;do echo "\"$$i\":{\"llvm-ir\":\"$(BUILD_DIR)/$${i/.swift/.ll}\",\"llvm-bc\":\"$(BUILD_DIR)/$${i/%.swift/.bc}\"},";done;echo "}") > $@

$(VERSION_FILE):
	git describe --long --dirty=-D --broken=-B |\
    sed -nEe 's/(.*)/public var USWIFT_VERSION: StaticString { "\1" },public var USWIFT_ARCH: StaticString { "$(ARCH)" },public var USWIFT_ARCH_BIT_WIDTH: UInt8 { $(ARCH_INT_BIT_WIDTH) }/p' |\
    tr ',' '\n' > $@

$(BUILD_DIR):
	mkdir -p $@

$(MODULE_NAME): $(BUILD_DIR)/$(MODULE_NAME).swiftmodule $(BUILD_DIR)/$(SWIFT_ONONE_MODULE).swiftmodule

# ==> modules
$(BUILD_DIR)/$(MODULE_NAME).swiftmodule: $(ALL_SWIFT_SOURCES) | $(BUILD_DIR)
	@echo "** Create Swift module"
	@-rm $@ 2> /dev/null || true # not sure why this is needed, but the build module command was either not updating the module or was leaving timestamp so make kept remaking it, annoyingly
	"$(SWIFTC)" $(SWIFT_EXTRA_OPTS) -Osize -whole-module-optimization -emit-module -emit-module-path $@ -module-name $(MODULE_NAME) $^

$(BUILD_DIR)/$(SWIFT_ONONE_MODULE).swiftmodule: $(SWIFT_ONONE_DIR)/$(SWIFT_ONONE_MODULE).swift | $(BUILD_DIR)
	@echo "** Create SwiftOnone module"
	"$(SWIFTC)" $(SWIFT_EXTRA_OPTS) -Osize -whole-module-optimization -emit-module -emit-module-path $@ -module-name $(SWIFT_ONONE_MODULE) $^

MODULE_FILES_TO_INSTALL = Swift.swiftmodule Swift.swiftdoc SwiftOnoneSupport.swiftmodule SwiftOnoneSupport.swiftdoc

# ==> other
clean:
	rm -rf bin

USWIFT_ARCH_BINARY_REPOSITORY_STAGING_CORE_PATH = $(USWIFT_ARCH_BINARY_REPOSITORY_STAGING_PATH)/$(CORE)

update-binary-repository: all
	mkdir -p "$(USWIFT_ARCH_BINARY_REPOSITORY_STAGING_PATH)"
	cp $(patsubst %,$(BUILD_DIR)/%,$(MODULE_FILES_TO_INSTALL)) "$(USWIFT_ARCH_BINARY_REPOSITORY_STAGING_PATH)"/
	cp -r $(patsubst %,$(BUILD_DIR)/%,$(CORES)) "$(USWIFT_ARCH_BINARY_REPOSITORY_STAGING_PATH)"/
	rm $(patsubst %,"$(USWIFT_ARCH_BINARY_REPOSITORY_STAGING_PATH)"/%/*.d,$(CORES))


# 	rm -rf "$(S4A_DEPLOYMENT_DIR)"
# 	git clone $(S4A_REPOSITORY_URL) "$(S4A_DEPLOYMENT_DIR)"
# 	git -C "$(S4A_DEPLOYMENT_DIR)" submodule update --init $(USWIFT_ARCH_BINARY_REPOSITORY_STAGING_CHECKOUT_PATH)

update-github-binaries: all
	git clone "$(USWIFT_ARCH_BINARY_REPOSITORY_URL)" "$(USWIFT_ARCH_BINARY_REPOSITORY_STAGING_CHECKOUT_PATH)"
	mkdir -p "$(USWIFT_ARCH_BINARY_REPOSITORY_STAGING_PATH)"
	cp $(patsubst %,$(BUILD_DIR)/%,$(MODULE_FILES_TO_INSTALL)) "$(USWIFT_ARCH_BINARY_REPOSITORY_STAGING_PATH)"/
	cp -r $(patsubst %,$(BUILD_DIR)/%,$(CORES)) "$(USWIFT_ARCH_BINARY_REPOSITORY_STAGING_PATH)"/
	rm $(patsubst %,"$(USWIFT_ARCH_BINARY_REPOSITORY_STAGING_PATH)"/%/*.d,$(CORES))
	git -C "$(USWIFT_ARCH_BINARY_REPOSITORY_STAGING_CHECKOUT_PATH)" add .
	git -C "$(USWIFT_ARCH_BINARY_REPOSITORY_STAGING_CHECKOUT_PATH)" commit -am 'automatic repo update'
	git -C "$(USWIFT_ARCH_BINARY_REPOSITORY_STAGING_CHECKOUT_PATH)" push

.PHONY : all clean cores install touchvars $(MODULE_NAME) $(CORES)
.INTERMEDIATE: $(VERSION_FILE)
