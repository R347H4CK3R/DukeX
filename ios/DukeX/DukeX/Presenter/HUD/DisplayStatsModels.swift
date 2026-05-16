import Foundation

struct DukeXDisplayStats {
    var sampleID: UInt64 = 0
    var presenterFPS: Double = 0
    var nv2aFPS: UInt32 = 0
    var mspf: Int32 = 0
    var frames: UInt64 = 0
    var presentReadyFrames: UInt64 = 0
    var presentMissedFrames: UInt64 = 0
    var nativePresentFrames: UInt64 = 0
    var pvideoFrames: UInt64 = 0
    var surfaceUploadPendingFrames: UInt64 = 0
    var finishPresentingFrames: UInt64 = 0
    var avgTotalUS: Int64 = 0
    var avgWaitPresentUS: Int64 = 0
    var avgSubmitUS: Int64 = 0
    var avgPresentUS: Int64 = 0
    var queueSubmits: Int32 = 0
    var auxSubmits: Int32 = 0
    var displaySubmits: Int32 = 0
    var shaderBinds: Int32 = 0
    var surfaceDownloads: Int32 = 0
    var surfaceToTexture: Int32 = 0
    var geometryUpdates: Int32 = 0
    var geometryRAMUpdates: Int32 = 0
    var geometryIndexUpdates: Int32 = 0
    var geometryInlineUpdates: Int32 = 0
    var pipelineGenerations: Int32 = 0
    var shaderGenerations: Int32 = 0
    var textureUploads: Int32 = 0
    var surfaceUploads: Int32 = 0
}

struct AppResourceStats {
    let cpuPercent: Double
    let residentMemoryBytes: UInt64
    let thermalState: ProcessInfo.ThermalState
}
