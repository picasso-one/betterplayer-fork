class BetterPlayerBitrateConfiguration {
  final BitrateConfiguration bitrateConfiguration;
  final int? maxVideoBitrateBps;

  BetterPlayerBitrateConfiguration({required this.bitrateConfiguration, this.maxVideoBitrateBps});
}

enum BitrateConfiguration { auto, max }
