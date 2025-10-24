MT7628-only Ethernet Driver (DTS-driven autopoll/power)
-------------------------------------------------------
Place under: drivers/net/ethernet/ralink/mt7628
Enable with: CONFIG_NET_RALINK_MT7628=y

Integration:
  - ralink/Makefile:  obj-$(CONFIG_NET_RALINK_MT7628) += mt7628/
  - ralink/Kconfig :  source "drivers/net/ethernet/ralink/mt7628/Kconfig"

Notes:
  - Autopoll mask is built from DTS (phy-handle per port).
  - Only PHYs present in the mask are powered; others are set BMCR_PDOWN.
