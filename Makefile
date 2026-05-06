# HyperCaps — Caps Lock as a hyper modifier.
#
# Release pipeline delegated to the shared `release.mk` from
# PerpetualBeta/jorvik-release. SPM project, embedded Sparkle,
# dual-ship (.zip + .pkg).

BUNDLE_NAME      := HyperCaps
BUNDLE_TYPE      := app
PRODUCT_NAME     := HyperCaps.app
BUNDLE_ID        := cc.jorviksoftware.HyperCaps
BUILD_SYSTEM     := spm
SPM_PRODUCT      := HyperCaps

PACKAGE_TYPE     := zip
ALSO_SHIP_PKG    := true
EMBEDDED_FRAMEWORKS := Sparkle
ENTITLEMENTS     := HyperCaps.entitlements

include ../jorvik-release/release.mk
