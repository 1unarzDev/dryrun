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
    public var siteHazards: SiteHazardProfile?
    public var homeID: String?
    public var stableHomeID: String { homeID ?? "home-\(id)" }
    public var preparedness: PreparednessRecord?
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
        privateLocation: PrivateLocation? = nil, homeID: String? = nil, preparedness: PreparednessRecord? = nil, people: [Person], pets: [Pet] = [], housing: Housing,
        equipment: [PoweredEquipment] = [], backupPower: [BackupPowerSource] = [],
        communications: Communications = Communications(), transport: Transport, supplies: Supplies,
        contacts: [HouseholdContact] = [], completedPreparations: [CompletedPreparation] = [],
        isFictional: Bool = false, updatedAt: Date? = nil
    ) {
        self.id = id; self.revision = revision; self.schemaVersion = Self.schemaVersion
        self.displayName = displayName; self.preferredLocale = preferredLocale; self.regionID = regionID
        self.privateLocation = privateLocation; self.homeID = homeID; self.preparedness = preparedness; self.people = people; self.pets = pets; self.housing = housing
        self.equipment = equipment; self.backupPower = backupPower; self.communications = communications
        self.transport = transport; self.supplies = supplies; self.contacts = contacts
        self.completedPreparations = completedPreparations; self.isFictional = isFictional; self.updatedAt = updatedAt
    }

    public mutating func invalidateBackupCompatibility(for sourceID: String) {
        for index in equipment.indices where equipment[index].compatibleBackupIDs.contains(sourceID) {
            equipment[index].compatibleBackupIDs.removeAll { $0 == sourceID }
            equipment[index].documentedBackupRuntimeHours = .unknown
        }
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
    public var unit: String?
    public var city: String?
    public var administrativeArea: String?
    public var postalCode: String?
    public var countryCode: String?
    public init(addressLine: String? = nil, latitude: Double? = nil, longitude: Double? = nil, unit: String? = nil, city: String? = nil, administrativeArea: String? = nil, postalCode: String? = nil, countryCode: String? = nil) {
        self.unit = unit; self.city = city; self.administrativeArea = administrativeArea; self.postalCode = postalCode; self.countryCode = countryCode
        self.addressLine = addressLine; self.latitude = latitude; self.longitude = longitude
    }
}

public enum AgeBand: String, Codable, Sendable, Hashable, CaseIterable {
    case unknown, infant, child, teen, adult, olderAdult
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
    public var isSelf: Bool?
    public var relationship: FamilyRelationship?
    public var customRelationship: String?
    public var emergencyInformation: PersonEmergencyInformation?
    public init(id: String, alias: String, ageBand: AgeBand, needs: [AssistanceNeed] = [],
                communicationNotes: String? = nil, sleepingSpaceID: String? = nil, helperPersonID: String? = nil, isSelf: Bool? = nil, relationship: FamilyRelationship? = nil, customRelationship: String? = nil, emergencyInformation: PersonEmergencyInformation? = nil) {
        self.isSelf = isSelf; self.relationship = relationship; self.customRelationship = customRelationship; self.emergencyInformation = emergencyInformation
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
    /// Nil preserves an unknown legacy medication-storage answer.
    public var refrigeratedStorage: EvidenceValue<Bool>?
    /// Optional explicit power requirement; medication defaults to no direct electrical load.
    public var electricalRequirement: EvidenceValue<Bool>?
    public var legacyOriginalLabel: String?
    public var labelIsCustom: Bool?
    public var storageInstructions: String?
    public var storagePlanConfirmed: EvidenceValue<Bool>?
    public var requiresElectricalPower: Bool { electricalRequirement?.value ?? (purpose != .refrigeratedMedication) }
    public var requiresColdStorage: Bool { refrigeratedStorage?.value ?? (purpose == .refrigeratedMedication || needsRefrigeration) }

    /// A type edit changes the support question. Existing compatibility/runtime cannot certify the new type.
    /// Names and original imported data remain available; user-authored clinical instructions are retained.
    public mutating func changePurpose(to value: EquipmentPurpose) {
        guard purpose != value else { return }
        purpose = value
        electricalRequirement = nil
        refrigeratedStorage = nil
        needsRefrigeration = false
        compatibleBackupIDs = []
        documentedBackupRuntimeHours = .unknown
        powerWatts = .unknown
        storagePlanConfirmed = nil
        verifiedAt = nil
    }

    public init(id: String, purpose: EquipmentPurpose, label: String, personID: String? = nil, isEssential: Bool = true,
                compatibleBackupIDs: [String] = [], documentedBackupRuntimeHours: EvidenceValue<Double> = .unknown,
                powerWatts: EvidenceValue<Double> = .unknown, needsRefrigeration: Bool = false,
                verifiedAt: Date? = nil, carePlanNotes: String? = nil, refrigeratedStorage: EvidenceValue<Bool>? = nil, electricalRequirement: EvidenceValue<Bool>? = nil, storageInstructions: String? = nil, storagePlanConfirmed: EvidenceValue<Bool>? = nil) {
        self.id = id; self.purpose = purpose
        if label == Self.legacyDefaultLabels[purpose] { self.label = ""; self.legacyOriginalLabel = label; self.labelIsCustom = false }
        else { self.label = label; self.labelIsCustom = !label.isEmpty }
        self.personID = personID; self.isEssential = isEssential
        self.compatibleBackupIDs = compatibleBackupIDs; self.documentedBackupRuntimeHours = documentedBackupRuntimeHours
        self.powerWatts = powerWatts; self.needsRefrigeration = needsRefrigeration; self.verifiedAt = verifiedAt
        self.storageInstructions = storageInstructions; self.storagePlanConfirmed = storagePlanConfirmed
        self.carePlanNotes = carePlanNotes; self.refrigeratedStorage = refrigeratedStorage; self.electricalRequirement = electricalRequirement
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
    public var legacyOriginalLabel: String?
    public var labelIsCustom: Bool?
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

    public mutating func changeKind(to value: BackupPowerKind) {
        guard kind != value else { return }
        kind = value
        usableEnergyWh = .unknown
        continuousOutputW = .unknown
        setupConfirmed = .unknown
        islandingConfirmed = .unknown
        safeOutdoorPlacementConfirmed = .unknown
    }

    public init(id: String, kind: BackupPowerKind, label: String, usableEnergyWh: EvidenceValue<Double> = .unknown,
                continuousOutputW: EvidenceValue<Double> = .unknown, setupConfirmed: EvidenceValue<Bool> = .unknown,
                islandingConfirmed: EvidenceValue<Bool> = .unknown,
                safeOutdoorPlacementConfirmed: EvidenceValue<Bool> = .unknown, assumedEfficiency: Double = 0.85) {
        self.id = id; self.kind = kind
        if label == Self.legacyDefaultLabels[kind] { self.label = ""; self.legacyOriginalLabel = label; self.labelIsCustom = false }
        else { self.label = label; self.labelIsCustom = !label.isEmpty }
 self.usableEnergyWh = usableEnergyWh
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
    case outOfAreaContact, neighborHelper, transportSupport, careProvider, utilityMedicalRegistry, waterUtility, other
}

public struct HouseholdContact: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var role: ContactRole
    public var alias: String
    public var phone: String?
    public var relationship: String?
    public var hasUsablePhone: Bool { phone.map { $0.filter(\.isNumber).count >= 3 && $0.filter(\.isNumber).count <= 15 } ?? false }
    public var isComplete: Bool { !alias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && hasUsablePhone }
    public var telephoneURL: URL? {
        guard hasUsablePhone, let phone else { return nil }
        let number = phone.filter { $0.isNumber || $0 == "+" }
        return URL(string: "tel:\(number)")
    }
    public init(id: String, role: ContactRole, alias: String, phone: String? = nil, relationship: String? = nil) {
        self.id = id; self.role = role; self.alias = alias; self.phone = phone; self.relationship = relationship
    }
}

public struct CompletedPreparation: Codable, Sendable, Hashable {
    public var actionID: String
    public var subjectID: String?
    public var factFingerprint: String?
    public var taskID: String { subjectID.map { "\(actionID)|\($0)" } ?? actionID }
    public var completedAt: Date
    public var note: String?
    public init(actionID: String, completedAt: Date, note: String? = nil, subjectID: String? = nil, factFingerprint: String? = nil) {
        self.actionID = actionID; self.completedAt = completedAt; self.note = note; self.subjectID = subjectID; self.factFingerprint = factFingerprint
    }
}

public enum FamilyRelationship: String, Codable, Sendable, Hashable, CaseIterable {
    case mother, father, parent, guardian, child, grandparent, greatGrandparent, aunt, uncle, sibling, spousePartner, caregiver, otherHouseholdMember, custom
}

public struct PersonEmergencyInformation: Codable, Sendable, Hashable {
    public var criticalConditions: String
    public var severeAllergies: String
    public var essentialMedication: String
    public var responderInstructions: String
    public var reviewedAt: Date?
    public init(criticalConditions: String = "", severeAllergies: String = "", essentialMedication: String = "", responderInstructions: String = "", reviewedAt: Date? = nil) {
        self.criticalConditions = criticalConditions; self.severeAllergies = severeAllergies
        self.essentialMedication = essentialMedication; self.responderInstructions = responderInstructions; self.reviewedAt = reviewedAt
    }
}

/// Explicit household records; recording location never implies a functional check.
public struct PreparednessRecord: Codable, Sendable, Hashable {
    public var items: [String: PreparationFact]
    /// Review of the current card and contacts; does not imply other family members participated.
    public var reviewedAt: Date?
    /// Explicit joint review only. Absent in legacy records and never inferred from a solo card review.
    public var jointlyReviewedAt: Date?
    public init(items: [String: PreparationFact] = [:], reviewedAt: Date? = nil, jointlyReviewedAt: Date? = nil) {
        self.items = items; self.reviewedAt = reviewedAt; self.jointlyReviewedAt = jointlyReviewedAt
    }
}
public struct PreparationFact: Codable, Sendable, Hashable {
    public var available: EvidenceValue<Bool>
    public var location: String
    public var checkedAt: Date?
    public var coverageReviewed: EvidenceValue<Bool>?
    public var familyAware: EvidenceValue<Bool>?
    public var notes: String
    public init(available: EvidenceValue<Bool> = .unknown, location: String = "", checkedAt: Date? = nil, notes: String = "", coverageReviewed: EvidenceValue<Bool>? = nil, familyAware: EvidenceValue<Bool>? = nil) {
        self.available = available; self.location = location; self.checkedAt = checkedAt; self.notes = notes; self.coverageReviewed = coverageReviewed; self.familyAware = familyAware
    }

    /// A physical check, coverage review or family location-awareness record applies to the recorded
    /// item at its recorded location. Editing those facts requires fresh evidence; notes alone do not.
    /// Forms apply this on each edit so users can explicitly record a new check after the change.
    public func applyingEdits(_ proposed: PreparationFact) -> PreparationFact {
        guard available.value != proposed.available.value || available.status != proposed.available.status
                || location != proposed.location else { return proposed }
        var result = proposed
        result.checkedAt = nil
        result.coverageReviewed = nil
        result.familyAware = nil
        return result
    }
}

extension PoweredEquipment {
    private static let legacyDefaultLabels: [EquipmentPurpose: String] = [.oxygenConcentrator: "Oxygen concentrator", .cpapOrBipap: "CPAP or BiPAP", .powerWheelchair: "Power wheelchair", .refrigeratedMedication: "Refrigerated medication", .homeDialysis: "Home dialysis", .suction: "Suction", .feedingPump: "Feeding pump", .communicationDevice: "Communication device", .other: "Other"]
    public func localizedLabel(_ localizer: Localizer) -> String { label.isEmpty ? localizer("equipment.\(purpose.rawValue)") : label }
    private enum CodingKeys: String, CodingKey {
        case id, purpose, label, personID, isEssential, compatibleBackupIDs, documentedBackupRuntimeHours, powerWatts,
             needsRefrigeration, verifiedAt, carePlanNotes, refrigeratedStorage, electricalRequirement, legacyOriginalLabel, labelIsCustom, storageInstructions, storagePlanConfirmed
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        purpose = try c.decode(EquipmentPurpose.self, forKey: .purpose)
        let oldLabel = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        // Only the documented default for this exact type is recognized. A different name is preserved.

        legacyOriginalLabel = try c.decodeIfPresent(String.self, forKey: .legacyOriginalLabel)
        labelIsCustom = try c.decodeIfPresent(Bool.self, forKey: .labelIsCustom)
        if labelIsCustom != true, legacyOriginalLabel == nil, oldLabel == Self.legacyDefaultLabels[purpose] { label = ""; legacyOriginalLabel = oldLabel; labelIsCustom = false }
        else { label = oldLabel; if labelIsCustom == nil { labelIsCustom = !oldLabel.isEmpty } }
        personID = try c.decodeIfPresent(String.self, forKey: .personID)
        isEssential = try c.decodeIfPresent(Bool.self, forKey: .isEssential) ?? true
        compatibleBackupIDs = try c.decodeIfPresent([String].self, forKey: .compatibleBackupIDs) ?? []
        documentedBackupRuntimeHours = try c.decodeIfPresent(EvidenceValue<Double>.self, forKey: .documentedBackupRuntimeHours) ?? .unknown
        powerWatts = try c.decodeIfPresent(EvidenceValue<Double>.self, forKey: .powerWatts) ?? .unknown
        needsRefrigeration = try c.decodeIfPresent(Bool.self, forKey: .needsRefrigeration) ?? false
        verifiedAt = try c.decodeIfPresent(Date.self, forKey: .verifiedAt)
        carePlanNotes = try c.decodeIfPresent(String.self, forKey: .carePlanNotes)
        refrigeratedStorage = try c.decodeIfPresent(EvidenceValue<Bool>.self, forKey: .refrigeratedStorage)
        electricalRequirement = try c.decodeIfPresent(EvidenceValue<Bool>.self, forKey: .electricalRequirement)
        storageInstructions = try c.decodeIfPresent(String.self, forKey: .storageInstructions)
        storagePlanConfirmed = try c.decodeIfPresent(EvidenceValue<Bool>.self, forKey: .storagePlanConfirmed)
    }
}

extension BackupPowerSource {
    private static let legacyDefaultLabels: [BackupPowerKind: String] = [.portableBatteryStation: "Portable battery station", .portableGenerator: "Portable generator", .standbyGenerator: "Standby generator", .solarWithBattery: "Solar with battery", .solarGridTiedOnly: "Solar (grid-tied only)", .vehicleInverter: "Vehicle inverter", .powerBank: "Power bank", .deviceInternalBattery: "Device's own battery"]
    public func localizedLabel(_ localizer: Localizer) -> String { label.isEmpty ? localizer("enum.\(kind.rawValue)") : label }
    private enum CodingKeys: String, CodingKey {
        case id, kind, label, legacyOriginalLabel, labelIsCustom, usableEnergyWh, continuousOutputW, setupConfirmed, islandingConfirmed, safeOutdoorPlacementConfirmed, assumedEfficiency
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id); kind = try c.decode(BackupPowerKind.self, forKey: .kind)
        let original = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        legacyOriginalLabel = try c.decodeIfPresent(String.self, forKey: .legacyOriginalLabel)
        labelIsCustom = try c.decodeIfPresent(Bool.self, forKey: .labelIsCustom)
        if labelIsCustom != true, legacyOriginalLabel == nil, original == Self.legacyDefaultLabels[kind] { label = ""; legacyOriginalLabel = original; labelIsCustom = false }
        else { label = original; if labelIsCustom == nil { labelIsCustom = !original.isEmpty } }
        usableEnergyWh = try c.decodeIfPresent(EvidenceValue<Double>.self, forKey: .usableEnergyWh) ?? .unknown
        continuousOutputW = try c.decodeIfPresent(EvidenceValue<Double>.self, forKey: .continuousOutputW) ?? .unknown
        setupConfirmed = try c.decodeIfPresent(EvidenceValue<Bool>.self, forKey: .setupConfirmed) ?? .unknown
        islandingConfirmed = try c.decodeIfPresent(EvidenceValue<Bool>.self, forKey: .islandingConfirmed) ?? .unknown
        safeOutdoorPlacementConfirmed = try c.decodeIfPresent(EvidenceValue<Bool>.self, forKey: .safeOutdoorPlacementConfirmed) ?? .unknown
        assumedEfficiency = try c.decodeIfPresent(Double.self, forKey: .assumedEfficiency) ?? 0.85
    }
}

extension Person {
    /// The self label is presentation, never a guessed personal name or relationship.
    public func localizedLabel(_ localizer: Localizer) -> String {
        alias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? localizer(isSelf == true ? "family.you" : "ui.person") : alias
    }
}
