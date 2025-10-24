###############################################################################
# MT7628 Ethernet driver (subdir)
#
# We aggregate existing ralink sources from the parent directory into a single
# mt7628.o using a composite object list. The sources remain in the parent
# directory; Kbuild supports relative paths here.
###############################################################################

obj-$(CONFIG_RAETH_MT7628) += mt7628.o

mt7628-objs := \
	gsw_mt7620.o \
	mdio.o \
	mdio_mt7620.o \
	ethtool.o \
	mtk_eth_soc.o \
	soc_mt7620.o
