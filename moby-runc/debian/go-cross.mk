# https://pkg.go.dev/cmd/go#hdr-Environment_variables
# https://go.dev/doc/install/source#environment

# TODO experiments for https://bugs.debian.org/960842

# if you want "cgo" too, export CGO_ENABLED = 1 and include /usr/share/dpkg/buildtools.mk with DPKG_EXPORT_BUILDTOOLS = 1 set (and if not, you probably want to explicitly export CGO_EANBLED = 0)

include /usr/share/dpkg/architecture.mk

# linux is the only OS actually supported here, but this should make things break if we ever get anything else (like kfreebsd)
export GOOS ?= $(DEB_HOST_ARCH_OS)

export GOARCH ?= $(patsubst i386,386,$(DEB_HOST_ARCH_CPU:el=le))
ifeq ($(GOARCH),386)
  # TODO if Debian less than Trixie, do not use sse2 (GO386 = softfloat); http://bugs.debian.org/753160
  export GO386 ?= sse2
else ifeq ($(GOARCH),arm)
  ifeq ($(DEB_HOST_ARCH_ABI),eabi)
    export GOARM ?= 5
  else
    include /usr/share/dpkg/vendor.mk
    ifeq ($(shell $(call dpkg_vendor_derives_from,raspbian)),yes)
      export GOARM ?= 6
    else
      export GOARM ?= 7
    endif
  endif
endif
# TODO explicit GOAMD64 GOARM64 GOMIPS GOMIPS64 GOPPC64 GORISCV64 ?

# TODO export GOHOSTOS ?= $(DEB_BUILD_ARCH_OS) # lmao
# TODO export GOHOSTARCH ?= $(patsubst i386,386,$(DEB_BUILD_ARCH_CPU:el=le))
# (these are only relevant for building the compiler, but they're harmless to set otherwise -- maybe we set them conditionally based on an ifdef ?)
