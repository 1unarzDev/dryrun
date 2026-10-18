import Foundation

/// Preserves a room association only when its identity is supported. Room numbers in a new capture
/// are display ordering, not evidence that the same person still sleeps in the same physical room.
public enum HomeRoomAssociations {
    public static func remappedRoomID(_ roomID: String?, from previous: HomeModel?, to updated: HomeModel) -> String? {
        guard let roomID, let previous, previous.id == updated.id,
              let oldRoom = previous.space(roomID) else { return nil }
        if previous.source == .roomPlanScan || updated.source == .roomPlanScan {
            guard previous.source == .roomPlanScan, updated.source == .roomPlanScan else { return nil }
            if let oldFrame = previous.sourceCaptureFrameID, let newFrame = updated.sourceCaptureFrameID {
                guard oldFrame == newFrame, let sourceID = oldRoom.sourceScanRoomID else { return nil }
                let matches = updated.spaces.filter { $0.sourceScanRoomID == sourceID }
                return matches.count == 1 ? matches[0].id : nil
            }
            // Legacy scans have no capture lineage. An unchanged room can survive an ordinary edit;
            // changed/reordered ordinal records cannot silently claim the same physical room.
            guard previous.sourceCaptureFrameID == nil, updated.sourceCaptureFrameID == nil,
                  let same = updated.space(roomID), same == oldRoom else { return nil }
            return roomID
        }
        guard previous.source == updated.source, updated.space(roomID) != nil else { return nil }
        return roomID
    }
}
