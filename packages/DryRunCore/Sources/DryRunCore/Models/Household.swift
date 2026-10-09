import Foundation

// APP-OWNED conceptual contract. Owner: lead. Request changes through docs/CONTRACTS.md.
// Aliases rather than legal names; no diagnosis is ever required.

public struct HouseholdProfile: Codable, Sendable, Hashable, Identifiable {
    public static let schemaVersion = 1

    public var id: String
    /// Monotonic. Any edit that can change a result must bump this (see `bumpRevision`).
    public var revision: Int
    public var schemaVersion: Int
    public var displayName: String
    /// "en", "es", or "vi" in the first build.
    public var preferredLocale: String
    /// Allowlisted public region ID (county FIPS such as "48143"). Never an address.
    public var regionID: String
    /// Optional private location. Stays in the encrypted vault; never sent to the Dry Run backend.
    public var privateLocation: PrivateLocation?
    public var people: [Person]
    public var pets: [Pet]
    public var housing: Housing
    public var equipment: [PoweredEquipment]
    public var backupPower: [BackupPowerSource]
    public var communications: Communications
    public var transport: Transport
    public var supplies: Supplies
    public var contacts: [HouseholdContact]
    /// Real preparation state, changed only by explicit "Mark preparation completed".
    public var completedPreparations: [CompletedPreparation]
    /// True for bundled fictional demo households.
    public var isFictional: Bool
    public var updatedAt: Date?

    public init(
        id: String, revision: Int = 1, displayName: String, preferredLocale: String = "en", regionID: String,
        privateLocation: PrivateLocation? = nil, people: [Person], pets: [Pet] = [], housing: Housing,
        equipment: [PoweredEquipment] = [], backupPower: [BackupPowerSource] = [],
        communications: Communications = Communications(), transport: Transport, supplies: Supplies,
        contacts: [HouseholdContact] = [], completedPreparations: [CompletedPreparation] = [],
        isFictional: Bool = false, updatedAt: Date? = nil
    ) {
        self.id = id; self.revision = revision; self.schemaVersion = Self.schemaVersion
        self.displayName = displayName; self.preferredLocale = preferredLocale; self.regionID = regionID
        self.privateLocation = privateLocation; self.people = people; self.pets = pets; self.housing = housing
        self.equipment = equipment; self.backupPower = backupPower; self.communications = communications
        self.transport = transport; self.supplies = supplies; self.contacts = contacts
        self.completedPreparations = completedPreparations; self.isFictional = isFictional; self.updatedAt = updatedAt
    }

    public mutating func bumpRevision(at date: Date = Date()) {
        revision += 1
        updatedAt = date
    }
}

public struct PrivateLocation: Codable, Sendable, Hashable {
    public var addressLine: String?
    public var latitude: Double?
    public var longitude: Double?
    public init(addressLine: String? = nil, latitude: Double? = nil, longitude: Double? = nil) {
        self.addressLine = addressLine; self.latitude = latitude; self.longitude = longitude
    }
}

public enum AgeBand: String, Codable, Sendable, Hashable, CaseIterable {
    case infant, child, teen, adult, olderAdult
}

public enum AssistanceNeed: String, Codable, Sendable, Hashable, CaseIterable {
    case usesWheelchair
    case cannotUseStairs
    case limitedMobility
    case needsHelperToEvacuate
    case deafOrHardOfHearing
    case blindOrLowVision
    case cognitiveOrMemory
    case communicationSupport
    case heatSensitive
    case coldSensitive
}

public struct Person: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var alias: String
    public var ageBand: AgeBand
    public var needs: [AssistanceNeed]
    public var communicationNotes: String?
    public var sleepingSpaceID: String?
    /// Person ID of the household member who helps this person, when appropriate.
    public var helperPersonID: String?
    public init(id: String, alias: String, ageBand: AgeBand, needs: [AssistanceNeed] = [],
                communicationNotes: String? = nil, sleepingSpaceID: String? = nil, helperPersonID: String? = nil) {
        self.id = id; self.alias = alias; self.ageBand = ageBand; self.needs = needs
        self.communicationNotes = communicationNotes; self.sleepingSpaceID = sleepingSpaceID; self.helperPersonID = helperPersonID
    }
    public var requiresStepFreeRoute: Bool { needs.contains(.usesWheelchair) || needs.contains(.cannotUseStairs) }
}

public enum PetKind: String, Codable, Sendable, Hashable, CaseIterable { case dog, cat, bird, smallAnimal, other }

public struct Pet: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var kind: PetKind
    public var count: Int
    public var carrierAvailable: EvidenceValue<Bool>
    public var notes: String?
    public init(id: String, kind: PetKind, count: Int = 1, carrierAvailable: EvidenceValue<Bool> = .unknown, notes: String? = nil) {
        self.id = id; self.kind = kind; self.count = count; self.carrierAvailable = carrierAvailable; self.notes = notes
    }
}

public enum HomeType: String, Codable, Sendable, Hashable, CaseIterable {
    case singleFamily, apartment, manufacturedHome, townhouse, duplex, other
}

public enum Tenancy: String, Codable, Sendable, Hashable, CaseIterable { case owner, renter, other }

public enum HeatingFuel: String, Codable, Sendable, Hashable, CaseIterable {
    case electric, naturalGas, propane, wood, none, unknown
}

public enum CoolingKind: String, Codable, Sendable, Hashable, CaseIterable {
    case centralAC, windowOrPortableAC, evaporative, fansOnly, none, unknown
}

public enum WaterSourceKind: String, Codable, Sendable, Hashable, CaseIterable {
    case municipal, privateWell, unknown
}

public enum SanitationKind: String, Codable, Sendable, Hashable, CaseIterable {
    case sewer, septicGravity, septicWithPump, unknown
}

public struct Housing: Codable, Sendable, Hashable {
    public var homeType: HomeType
    public var tenancy: Tenancy
    public var floorCount: Int
    public var heatingFuel: HeatingFuel
    /// Gas/propane systems may still need power for controls/blowers. Ask; never infer from fuel.
    public var heatingNeedsElectricity: EvidenceValue<Bool>
    public var cooling: CoolingKind
    public var waterSource: WaterSourceKind
    /// Only meaningful for a private well.
    public var wellPumpElectric: EvidenceValue<Bool>
    /// Usable pressure-tank volume, if known. Unknown is never invented.
    public var wellPressureTankGallons: EvidenceValue<Double>
    public var sanitation: SanitationKind

    public init(homeType: HomeType, tenancy: Tenancy, floorCount: Int = 1, heatingFuel: HeatingFuel,
                heatingNeedsElectricity: EvidenceValue<Bool> = .unknown, cooling: CoolingKind,
                waterSource: WaterSourceKind, wellPumpElectric: EvidenceValue<Bool> = .unknown,
                wellPressureTankGallons: EvidenceValue<Double> = .unknown, sanitation: SanitationKind = .sewer) {
        self.homeType = homeType; self.tenancy = tenancy; self.floorCount = floorCount; self.heatingFuel = heatingFuel
        self.heatingNeedsElectricity = heatingNeedsElectricity; self.cooling = cooling; self.waterSource = waterSource
        self.wellPumpElectric = wellPumpElectric; self.wellPressureTankGallons = wellPressureTankGallons; self.sanitation = sanitation
    }
}

public enum EquipmentPurpose: String, Codable, Sendable, Hashable, CaseIterable {
    case oxygenConcentrator, cpapOrBipap, powerWheelchair, refrigeratedMedication, homeDialysis,
         suction, feedingPump, communicationDevice, other
}

/// Essential powered equipment. User-selected purpose; no diagnosis. Never estimate a safe interruption window.
public struct PoweredEquipment: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var purpose: EquipmentPurpose
    public var label: String
    public var personID: String?
    public var isEssential: Bool
    /// Backup source IDs the household has CONFIRMED compatible with this device.
    public var compatibleBackupIDs: [String]
    /// Runtime documented by manufacturer/care plan for this device on its backup. Unknown stays unknown.
    public var documentedBackupRuntimeHours: EvidenceValue<Double>
    /// Draw used only for energy accounting when the household supplied it.
    public var powerWatts: EvidenceValue<Double>
    /// Needs refrigeration (e.g. some medications) rather than electricity directly.
    public var needsRefrigeration: Bool
    public var verifiedAt: Date?
    /// Private; excluded from exported plans unless intentionally included.
    public var carePlanNotes: String?

    public init(id: String, purpose: EquipmentPurpose, label: String, personID: String? = nil, isEssential: Bool = true,
                compatibleBackupIDs: [String] = [], documentedBackupRuntimeHours: EvidenceValue<Double> = .unknown,
                powerWatts: EvidenceValue<Double> = .unknown, needsRefrigeration: Bool = false,
                verifiedAt: Date? = nil, carePlanNotes: String? = nil) {
        self.id = id; self.purpose = purpose; self.label = label; self.personID = personID; self.isEssential = isEssential
        self.compatibleBackupIDs = compatibleBackupIDs; self.documentedBackupRuntimeHours = documentedBackupRuntimeHours
        self.powerWatts = powerWatts; self.needsRefrigeration = needsRefrigeration; self.verifiedAt = verifiedAt
        self.carePlanNotes = carePlanNotes
    }
}

public enum BackupPowerKind: String, Codable, Sendable, Hashable, CaseIterable {
    case portableBatteryStation, portableGenerator, standbyGenerator, solarWithBattery,
         solarGridTiedOnly, vehicleInverter, powerBank, deviceInternalBattery
}

/// A single backup source. Its energy and output cannot be allocated twice.
public struct BackupPowerSource: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var kind: BackupPowerKind
    public var label: String
    /// Usable stored energy (Wh). Unknown is not invented.
    public var usableEnergyWh: EvidenceValue<Double>
    /// Continuous output limit (W).
    public var continuousOutputW: EvidenceValue<Double>
    /// The household has actually set this up and tested it.
    public var setupConfirmed: EvidenceValue<Bool>
    /// Solar only: can operate islanded during a grid outage.
    public var islandingConfirmed: EvidenceValue<Bool>
    /// Generators only: a confirmed outdoor location >= 20 ft from windows, doors, vents [S20].
    public var safeOutdoorPlacementConfirmed: EvidenceValue<Bool>
    /// Assumed conversion efficiency (0..1) for energy accounting. Stated, never hidden.
    public var assumedEfficiency: Double

    public init(id: String, kind: BackupPowerKind, label: String, usableEnergyWh: EvidenceValue<Double> = .unknown,
                continuousOutputW: EvidenceValue<Double> = .unknown, setupConfirmed: EvidenceValue<Bool> = .unknown,
                islandingConfirmed: EvidenceValue<Bool> = .unknown,
                safeOutdoorPlacementConfirmed: EvidenceValue<Bool> = .unknown, assumedEfficiency: Double = 0.85) {
        self.id = id; self.kind = kind; self.label = label; self.usableEnergyWh = usableEnergyWh
        self.continuousOutputW = continuousOutputW; self.setupConfirmed = setupConfirmed
        self.islandingConfirmed = islandingConfirmed; self.safeOutdoorPlacementConfirmed = safeOutdoorPlacementConfirmed
        self.assumedEfficiency = assumedEfficiency
    }
}

public struct Communications: Codable, Sendable, Hashable {
    public var handsetCount: Int
    /// Exercise assumption for a full handset charge in outage use (hours). Not a measured prediction.
    public var handsetRuntimeHours: EvidenceValue<Double>
    /// Full phone recharges available from power banks.
    public var powerBankCharges: EvidenceValue<Double>
    public var routerOnBackup: EvidenceValue<Bool>
    public var batteryOrCrankRadio: EvidenceValue<Bool>
    public init(handsetCount: Int = 1, handsetRuntimeHours: EvidenceValue<Double> = .assumed(18, unit: "h"),
                powerBankCharges: EvidenceValue<Double> = .unknown, routerOnBackup: EvidenceValue<Bool> = .unknown,
                batteryOrCrankRadio: EvidenceValue<Bool> = .unknown) {
        self.handsetCount = handsetCount; self.handsetRuntimeHours = handsetRuntimeHours
        self.powerBankCharges = powerBankCharges; self.routerOnBackup = routerOnBackup
        self.batteryOrCrankRadio = batteryOrCrankRadio
    }
}

public struct Vehicle: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var seats: Int
    public var wheelchairAccessible: EvidenceValue<Bool>
    public var isElectric: Bool
    public init(id: String, seats: Int, wheelchairAccessible: EvidenceValue<Bool> = .unknown, isElectric: Bool = false) {
        self.id = id; self.seats = seats; self.wheelchairAccessible = wheelchairAccessible; self.isElectric = isElectric
    }
}

public enum TransportAlternativeKind: String, Codable, Sendable, Hashable, CaseIterable {
    case friendOrFamily, paratransit, publicTransit, rideService, localEvacuationAssistance
}

public struct TransportAlternative: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var kind: TransportAlternativeKind
    public var contactID: String?
    public var wheelchairAccessible: EvidenceValue<Bool>
    /// The household has agreed this arrangement in advance.
    public var agreed: EvidenceValue<Bool>
    public init(id: String, kind: TransportAlternativeKind, contactID: String? = nil,
                wheelchairAccessible: EvidenceValue<Bool> = .unknown, agreed: EvidenceValue<Bool> = .unknown) {
        self.id = id; self.kind = kind; self.contactID = contactID
        self.wheelchairAccessible = wheelchairAccessible; self.agreed = agreed
    }
}

public enum DestinationKind: String, Codable, Sendable, Hashable, CaseIterable {
    case friendOrFamilyHome, hotel, publicWarmingOrCoolingSite, publicShelter, other
}

public struct RelocationDestination: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var kind: DestinationKind
    public var label: String
    /// Has power/heat/cooling been confirmed with the host? Public sites need source evidence of activation.
    public var conditionsConfirmed: EvidenceValue<Bool>
    public var acceptsPets: EvidenceValue<Bool>
    public var stepFreeAccess: EvidenceValue<Bool>
    public init(id: String, kind: DestinationKind, label: String, conditionsConfirmed: EvidenceValue<Bool> = .unknown,
                acceptsPets: EvidenceValue<Bool> = .unknown, stepFreeAccess: EvidenceValue<Bool> = .unknown) {
        self.id = id; self.kind = kind; self.label = label; self.conditionsConfirmed = conditionsConfirmed
        self.acceptsPets = acceptsPets; self.stepFreeAccess = stepFreeAccess
    }
}

public struct Transport: Codable, Sendable, Hashable {
    public var vehicles: [Vehicle]
    public var alternatives: [TransportAlternative]
    public var destinations: [RelocationDestination]
    public init(vehicles: [Vehicle] = [], alternatives: [TransportAlternative] = [], destinations: [RelocationDestination] = []) {
        self.vehicles = vehicles; self.alternatives = alternatives; self.destinations = destinations
    }
    /// "No car" is a first-class path, not an error.
    public var hasVehicle: Bool { !vehicles.isEmpty }
}

public struct Supplies: Codable, Sendable, Hashable {
    /// Confirmed stored potable water (US gallons). Unknown is not zero.
    public var storedWaterGallons: EvidenceValue<Double>
    public var shelfStableFoodDays: EvidenceValue<Double>
    public var flashlights: EvidenceValue<Int>
    public var coolerAndIcePacks: EvidenceValue<Bool>
    public var firstAidKit: EvidenceValue<Bool>
    public var fireExtinguisher: EvidenceValue<Bool>
    public var limitedStorageSpace: Bool
    public var limitedBudget: Bool
    public init(storedWaterGallons: EvidenceValue<Double> = .unknown, shelfStableFoodDays: EvidenceValue<Double> = .unknown,
                flashlights: EvidenceValue<Int> = .unknown, coolerAndIcePacks: EvidenceValue<Bool> = .unknown,
                firstAidKit: EvidenceValue<Bool> = .unknown, fireExtinguisher: EvidenceValue<Bool> = .unknown,
                limitedStorageSpace: Bool = false, limitedBudget: Bool = false) {
        self.storedWaterGallons = storedWaterGallons; self.shelfStableFoodDays = shelfStableFoodDays
        self.flashlights = flashlights; self.coolerAndIcePacks = coolerAndIcePacks; self.firstAidKit = firstAidKit
        self.fireExtinguisher = fireExtinguisher; self.limitedStorageSpace = limitedStorageSpace; self.limitedBudget = limitedBudget
    }
}

public enum ContactRole: String, Codable, Sendable, Hashable, CaseIterable {
    case outOfAreaContact, neighborHelper, transportSupport, careProvider, utilityMedicalRegistry, other
}

public struct HouseholdContact: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var role: ContactRole
    public var alias: String
    public var phone: String?
    public init(id: String, role: ContactRole, alias: String, phone: String? = nil) {
        self.id = id; self.role = role; self.alias = alias; self.phone = phone
    }
}

public struct CompletedPreparation: Codable, Sendable, Hashable {
    public var actionID: String
    public var completedAt: Date
    public var note: String?
    public init(actionID: String, completedAt: Date, note: String? = nil) {
        self.actionID = actionID; self.completedAt = completedAt; self.note = note
    }
}
