import Testing

@testable import CleanScopeCore

@Suite struct DiskWeatherTests {
  @Test func weatherCopyThresholds() {
    #expect(
      StoragePresentation.weatherLine(usedFraction: 0.69, availableBytes: 90_000_000_000, quickWinBytes: 0)
        == "Plenty of room.")
    #expect(
      StoragePresentation.weatherLine(usedFraction: 0.70, availableBytes: 70_000_000_000, quickWinBytes: 0)
        == "Getting cozy.")
    #expect(
      StoragePresentation.weatherLine(
        usedFraction: 0.88, availableBytes: 4_000_000_000, quickWinBytes: 1_850_000_000)
        == "Room is tight. 4 GB available. Quick wins can free 1.85 GB without touching your files.")
  }

  @Test func heroSublineByState() {
    func line(_ state: HeroState) -> String {
      StoragePresentation.heroSubline(
        state: state, itemsFound: 3, usedFraction: 0.75, availableBytes: 60_000_000_000,
        quickWinBytes: 1_000_000_000)
    }
    #expect(
      line(.idle)
        == "CleanScope checks known cleanup locations. Nothing is removed until you review it.")
    #expect(line(.scanning) == "3 items found so far.")
    #expect(line(.results) == "Getting cozy.")
    #expect(line(.cleaned) == "Getting cozy.")
  }

  @Test func tightRoomWithNothingSafeMakesNoPromise() {
    let line = StoragePresentation.weatherLine(
      usedFraction: 0.95, availableBytes: 4_000_000_000, quickWinBytes: 0)
    #expect(line == "Room is tight. 4 GB available.")
    #expect(!line.contains("free"))
  }

  @Test func unknownDiskTotalIsPlentyOfRoom() {
    let fraction = DiskWeather.usedFraction(totalBytes: 0, availableBytes: 0)
    #expect(fraction == 0)
    #expect(
      StoragePresentation.weatherLine(usedFraction: fraction, availableBytes: 0, quickWinBytes: 0)
        == "Plenty of room.")
  }

  @Test func usedFractionIsClampedToTheDisk() {
    #expect(DiskWeather.usedFraction(totalBytes: 1_000, availableBytes: 250) == 0.75)
    #expect(DiskWeather.usedFraction(totalBytes: 1_000, availableBytes: 2_000) == 0)
    #expect(DiskWeather.usedFraction(totalBytes: 1_000, availableBytes: -5) == 1)
  }

  @Test func stopsClampOutsideRange() {
    for dark in [false, true] {
      let low = DiskWeather.stops(usedFraction: 0.1, dark: dark)
      let floor = DiskWeather.stops(usedFraction: 0.40, dark: dark)
      #expect(low.top == floor.top && low.bottom == floor.bottom && low.sun == floor.sun)
      let high = DiskWeather.stops(usedFraction: 1.2, dark: dark)
      let ceiling = DiskWeather.stops(usedFraction: 0.98, dark: dark)
      #expect(high.top == ceiling.top && high.bottom == ceiling.bottom && high.sun == ceiling.sun)
    }
  }

  @Test func stopsRunFromFreshMorningToWarmAfternoon() {
    let fresh = DiskWeather.stops(usedFraction: 0.40, dark: false)
    #expect(fresh.top == 0xE3F1E8 && fresh.bottom == 0xF7F3EA)
    let warm = DiskWeather.stops(usedFraction: 0.98, dark: false)
    #expect(warm.top == 0xF8DDB2 && warm.bottom == 0xF4CB93)
    let freshDark = DiskWeather.stops(usedFraction: 0.40, dark: true)
    #expect(freshDark.top == 0x1F2E27 && freshDark.bottom == 0x1A1816)
    let warmDark = DiskWeather.stops(usedFraction: 0.98, dark: true)
    #expect(warmDark.top == 0x3A2C18 && warmDark.bottom == 0x2A2014)
  }

  @Test func stopsInterpolateBetweenTheEnds() {
    let mid = DiskWeather.stops(usedFraction: 0.69, dark: false)
    #expect(mid.top != 0xE3F1E8 && mid.top != 0xF8DDB2)
    #expect(mid.bottom != 0xF7F3EA && mid.bottom != 0xF4CB93)
  }

  @Test func weatherTextMeetsContrastAtBothEnds() {
    for used in [0.40, 0.98] {
      for dark in [false, true] {
        let stops = DiskWeather.stops(usedFraction: used, dark: dark)
        let text = dark ? BrandPalette.textPrimary.dark : BrandPalette.textPrimary.light
        #expect(BrandPalette.contrast(text, stops.top) >= 4.5)
        #expect(BrandPalette.contrast(text, stops.bottom) >= 4.5)
      }
    }
  }

  @Test func weatherNeverUsesDestructive() {
    for step in stride(from: 0.0, through: 1.0, by: 0.02) {
      for dark in [false, true] {
        let stops = DiskWeather.stops(usedFraction: step, dark: dark)
        for destructive in [
          BrandPalette.destructive.light, BrandPalette.destructive.dark,
          BrandPalette.destructive.increasedLight, BrandPalette.destructive.increasedDark,
        ] {
          #expect(stops.top != destructive && stops.bottom != destructive && stops.sun != destructive)
        }
      }
    }
  }
}
