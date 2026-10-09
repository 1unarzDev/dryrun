import Foundation

/// Clearly fictional demo households. No real people, addresses, or phone numbers.
/// Phone numbers use the reserved 555-01xx fictional range.
public enum SampleHouseholds {
    static let reference = ISO8601DateFormatter().date(from: "2026-10-01T12:00:00Z")!

    /// Rural Erath County. Electric private well, all-electric heat, an older adult using an
    /// oxygen concentrator, and a battery station whose compatibility has NOT been confirmed.
    /// Flagship freeze/power-loss cascade.
    public static var oak: HouseholdProfile {
        HouseholdProfile(
            id: "hh-oak",
            displayName: "Oak household (fictional)",
            preferredLocale: "en",
            regionID: "48143",
            people: [
                Person(id: "p-oak-1", alias: "Parent A", ageBand: .adult, sleepingSpaceID: "sp-bed1"),
                Person(id: "p-oak-2", alias: "Parent B", ageBand: .adult, sleepingSpaceID: "sp-bed1"),
                Person(id: "p-oak-3", alias: "Kid", ageBand: .child, sleepingSpaceID: "sp-bed2", helperPersonID: "p-oak-1"),
                Person(id: "p-oak-4", alias: "Grandpa", ageBand: .olderAdult, needs: [.limitedMobility, .coldSensitive],
                       sleepingSpaceID: "sp-living", helperPersonID: "p-oak-2"),
            ],
            pets: [Pet(id: "pet-oak-dog", kind: .dog, count: 1, carrierAvailable: .confirmed(false))],
            housing: Housing(
                homeType: .singleFamily, tenancy: .owner, floorCount: 1,
                heatingFuel: .electric, heatingNeedsElectricity: .confirmed(true),
                cooling: .centralAC, waterSource: .privateWell,
                wellPumpElectric: .confirmed(true), wellPressureTankGallons: .unknown,
                sanitation: .septicGravity
            ),
            equipment: [
                PoweredEquipment(id: "eq-oxygen", purpose: .oxygenConcentrator, label: "Oxygen concentrator",
                                 personID: "p-oak-4", isEssential: true, compatibleBackupIDs: [],
                                 documentedBackupRuntimeHours: .unknown, powerWatts: .unknown),
            ],
            backupPower: [
                BackupPowerSource(id: "bk-station", kind: .portableBatteryStation, label: "Portable battery station",
                                  usableEnergyWh: .confirmed(1000, unit: "Wh"), continuousOutputW: .confirmed(1200, unit: "W"),
                                  setupConfirmed: .unknown),
            ],
            communications: Communications(handsetCount: 3, handsetRuntimeHours: .assumed(18, unit: "h"),
                                           powerBankCharges: .confirmed(2), routerOnBackup: .confirmed(false),
                                           batteryOrCrankRadio: .unknown),
            transport: Transport(vehicles: [Vehicle(id: "veh-oak", seats: 5, wheelchairAccessible: .confirmed(false))],
                                 alternatives: [], destinations: []),
            supplies: Supplies(storedWaterGallons: .confirmed(5, unit: "gal"), shelfStableFoodDays: .confirmed(3),
                               flashlights: .confirmed(2), coolerAndIcePacks: .confirmed(true), firstAidKit: .confirmed(true),
                               fireExtinguisher: .confirmed(true)),
            contacts: [
                HouseholdContact(id: "ct-oak-1", role: .outOfAreaContact, alias: "Aunt in Abilene (fictional)", phone: "325-555-0142"),
            ],
            isFictional: true,
            updatedAt: reference
        )
    }

    /// Tarrant County apartment. Renters, no car, older adult who is heat-sensitive, prefers Vietnamese.
    public static var lake: HouseholdProfile {
        HouseholdProfile(
            id: "hh-lake",
            displayName: "Lake household (fictional)",
            preferredLocale: "vi",
            regionID: "48439",
            people: [
                Person(id: "p-lake-1", alias: "Bà (Grandma)", ageBand: .olderAdult, needs: [.heatSensitive, .limitedMobility],
                       communicationNotes: "Prefers Vietnamese", sleepingSpaceID: "sp-bed1", helperPersonID: "p-lake-2"),
                Person(id: "p-lake-2", alias: "Adult son", ageBand: .adult, sleepingSpaceID: "sp-bed2"),
            ],
            pets: [Pet(id: "pet-lake-cat", kind: .cat, count: 1, carrierAvailable: .confirmed(true))],
            housing: Housing(
                homeType: .apartment, tenancy: .renter, floorCount: 1,
                heatingFuel: .electric, heatingNeedsElectricity: .confirmed(true),
                cooling: .centralAC, waterSource: .municipal, sanitation: .sewer
            ),
            equipment: [
                PoweredEquipment(id: "eq-insulin", purpose: .refrigeratedMedication, label: "Refrigerated medication",
                                 personID: "p-lake-1", isEssential: true, needsRefrigeration: true),
            ],
            backupPower: [],
            communications: Communications(handsetCount: 2, handsetRuntimeHours: .assumed(18, unit: "h"),
                                           powerBankCharges: .unknown, routerOnBackup: .confirmed(false)),
            transport: Transport(vehicles: [], alternatives: [
                TransportAlternative(id: "ta-lake-bus", kind: .publicTransit, agreed: .unknown),
            ], destinations: []),
            supplies: Supplies(storedWaterGallons: .confirmed(2, unit: "gal"), shelfStableFoodDays: .unknown,
                               flashlights: .confirmed(1), limitedStorageSpace: true, limitedBudget: true),
            contacts: [
                HouseholdContact(id: "ct-lake-1", role: .neighborHelper, alias: "Neighbor in 2B (fictional)", phone: "817-555-0117"),
            ],
            isFictional: true,
            updatedAt: reference
        )
    }

    /// Hood County manufactured home. Wheelchair user; gas furnace whose blower dependency is unknown.
    public static var pine: HouseholdProfile {
        HouseholdProfile(
            id: "hh-pine",
            displayName: "Pine household (fictional)",
            preferredLocale: "es",
            regionID: "48221",
            people: [
                Person(id: "p-pine-1", alias: "Mamá", ageBand: .adult, sleepingSpaceID: "sp-bed1"),
                Person(id: "p-pine-2", alias: "Tío", ageBand: .adult, needs: [.usesWheelchair, .cannotUseStairs],
                       sleepingSpaceID: "sp-bed2", helperPersonID: "p-pine-1"),
                Person(id: "p-pine-3", alias: "Niña", ageBand: .child, sleepingSpaceID: "sp-bed2", helperPersonID: "p-pine-1"),
            ],
            pets: [],
            housing: Housing(
                homeType: .manufacturedHome, tenancy: .owner, floorCount: 1,
                heatingFuel: .naturalGas, heatingNeedsElectricity: .unknown,
                cooling: .windowOrPortableAC, waterSource: .municipal, sanitation: .septicWithPump
            ),
            equipment: [
                PoweredEquipment(id: "eq-chair", purpose: .powerWheelchair, label: "Power wheelchair charger",
                                 personID: "p-pine-2", isEssential: true),
            ],
            backupPower: [],
            communications: Communications(handsetCount: 2, handsetRuntimeHours: .assumed(18, unit: "h"),
                                           powerBankCharges: .confirmed(1), routerOnBackup: .confirmed(false)),
            transport: Transport(vehicles: [Vehicle(id: "veh-pine", seats: 5, wheelchairAccessible: .confirmed(false))],
                                 alternatives: [], destinations: []),
            supplies: Supplies(storedWaterGallons: .unknown, shelfStableFoodDays: .confirmed(2), flashlights: .confirmed(2),
                               fireExtinguisher: .unknown),
            contacts: [],
            isFictional: true,
            updatedAt: reference
        )
    }

    public static var all: [HouseholdProfile] { [oak, lake, pine] }
}
