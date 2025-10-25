#
# Makefile for the Ralink SoCs built-in ethernet macs
#

ralink-eth-$(CONFIG_NET_RALINK_MT7628)		+= mt7628/mtk_eth_soc.o \
						   mt7628/ethtool.o \
						   mt7628/mdio.o \
						   mt7628/mdio_mt7620.o \
						   mt7628/soc_mt7620.o

ifdef CONFIG_NET_RALINK_MT7628
obj-$(CONFIG_NET_RALINK_GSW_MT7620)		+= mt7628/gsw_mt7620.o mt7530.o
else
ralink-eth-y					+= mtk_eth_soc.o ethtool.o

ralink-eth-$(CONFIG_NET_RALINK_MDIO)		+= mdio.o
ralink-eth-$(CONFIG_NET_RALINK_MDIO_RT2880)	+= mdio_rt2880.o
ralink-eth-$(CONFIG_NET_RALINK_MDIO_MT7620)	+= mdio_mt7620.o

ralink-eth-$(CONFIG_NET_RALINK_RT2880)	+= soc_rt2880.o
ralink-eth-$(CONFIG_NET_RALINK_RT3050)	+= soc_rt3050.o
ralink-eth-$(CONFIG_NET_RALINK_RT3883)	+= soc_rt3883.o
ralink-eth-$(CONFIG_NET_RALINK_MT7620)	+= soc_mt7620.o

obj-$(CONFIG_NET_RALINK_ESW_RT3050)		+= esw_rt3050.o
obj-$(CONFIG_NET_RALINK_GSW_MT7620)		+= gsw_mt7620.o mt7530.o
endif

obj-$(CONFIG_NET_RALINK_SOC)			+= ralink-eth.o
