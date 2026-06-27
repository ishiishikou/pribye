import CoreGraphics
import Foundation
import SwiftData

enum DocumentProcessingStatus: String, Codable, CaseIterable {
  case captured
  case ocrProcessing
  case aiProcessing
  case ready
  case failed

  var userLabel: String {
    switch self {
    case .captured:
      return "画像処理中"
    case .ocrProcessing:
      return "OCR中"
    case .aiProcessing:
      return "AI解析中"
    case .ready:
      return "タスク化済み"
    case .failed:
      return "解析失敗"
    }
  }

  var isProcessing: Bool {
    switch self {
    case .captured, .ocrProcessing, .aiProcessing:
      return true
    case .ready, .failed:
      return false
    }
  }
}

enum DocumentLifecycleState: String, Codable, CaseIterable {
  case active
  case completed
  case archived
}

enum AnalysisFailureReason: String, Codable, CaseIterable, Error {
  case imageError = "IMAGE_ERROR"
  case ocrError = "OCR_ERROR"
  case extractionError = "EXTRACTION_ERROR"
  case unsupportedDevice = "UNSUPPORTED_DEVICE"
  case modelNotReady = "MODEL_NOT_READY"
  case modelLoadFailed = "MODEL_LOAD_FAILED"
  case unknownError = "UNKNOWN_ERROR"

  var message: String {
    switch self {
    case .imageError:
      return "画像の保存または補正に失敗しました。"
    case .ocrError:
      return "OCRに失敗しました。"
    case .extractionError:
      return "このプリントからタスクを抽出できませんでした。"
    case .unsupportedDevice:
      return "この端末ではAI解析を利用できません。"
    case .modelNotReady:
      return "AIモデルをダウンロードしてください。"
    case .modelLoadFailed:
      return "AIモデルの読み込みに失敗しました。"
    case .unknownError:
      return "解析中にエラーが発生しました。"
    }
  }
}

enum SourceImageState: String, Codable, CaseIterable {
  case available
  case deleted
  case permissionDenied
  case modified

  var message: String {
    switch self {
    case .available:
      return ""
    case .deleted:
      return "元画像は削除されています。抽出済み内容のみ表示しています。"
    case .permissionDenied:
      return "写真アクセスが許可されていないため、元画像とハイライトを表示できません。"
    case .modified:
      return "画像変更済みです。ハイライトを利用できません。"
    }
  }
}

enum TaskLifecycleState: String, Codable, CaseIterable {
  case active
  case completed
  case archived
}

@Model
final class DocumentRecord {
  @Attribute(.unique) var id: UUID
  var title: String
  var capturedAt: Date
  var distributedAt: Date?
  var statusRaw: String
  var lifecycleRaw: String
  var failureReasonRaw: String?
  var photoAssetIdentifier: String?
  var localImageFilename: String?
  var imageHash: String?
  var sourceImageStateRaw: String
  var thumbnailData: Data?
  var ocrText: String
  var correctedOCRText: String?

  @Relationship(deleteRule: .cascade, inverse: \PageRecord.document)
  var pages: [PageRecord]

  @Relationship(deleteRule: .cascade, inverse: \ExtractedTaskRecord.document)
  var tasks: [ExtractedTaskRecord]

  init(
    id: UUID = UUID(),
    title: String = "新しいプリント",
    capturedAt: Date = .now,
    status: DocumentProcessingStatus = .captured,
    lifecycle: DocumentLifecycleState = .active,
    sourceImageState: SourceImageState = .available
  ) {
    self.id = id
    self.title = title
    self.capturedAt = capturedAt
    self.statusRaw = status.rawValue
    self.lifecycleRaw = lifecycle.rawValue
    self.sourceImageStateRaw = sourceImageState.rawValue
    self.ocrText = ""
    self.correctedOCRText = nil
    self.pages = []
    self.tasks = []
  }

  var status: DocumentProcessingStatus {
    get { DocumentProcessingStatus(rawValue: statusRaw) ?? .failed }
    set { statusRaw = newValue.rawValue }
  }

  var lifecycle: DocumentLifecycleState {
    get { DocumentLifecycleState(rawValue: lifecycleRaw) ?? .active }
    set { lifecycleRaw = newValue.rawValue }
  }

  var failureReason: AnalysisFailureReason? {
    get { failureReasonRaw.flatMap(AnalysisFailureReason.init(rawValue:)) }
    set { failureReasonRaw = newValue?.rawValue }
  }

  var sourceImageState: SourceImageState {
    get { SourceImageState(rawValue: sourceImageStateRaw) ?? .available }
    set { sourceImageStateRaw = newValue.rawValue }
  }
}

@Model
final class PageRecord {
  @Attribute(.unique) var id: UUID
  var pageIndex: Int
  var photoAssetIdentifier: String?
  var localImageFilename: String?
  var imageHash: String?
  var cropTopLeftX: Double
  var cropTopLeftY: Double
  var cropTopRightX: Double
  var cropTopRightY: Double
  var cropBottomRightX: Double
  var cropBottomRightY: Double
  var cropBottomLeftX: Double
  var cropBottomLeftY: Double
  var ocrText: String
  var correctedOCRText: String?
  var document: DocumentRecord?

  @Relationship(deleteRule: .cascade, inverse: \OCRObservationRecord.page)
  var observations: [OCRObservationRecord]

  init(id: UUID = UUID(), pageIndex: Int, ocrText: String = "") {
    self.id = id
    self.pageIndex = pageIndex
    self.ocrText = ocrText
    self.correctedOCRText = nil
    self.cropTopLeftX = 0
    self.cropTopLeftY = 0
    self.cropTopRightX = 1
    self.cropTopRightY = 0
    self.cropBottomRightX = 1
    self.cropBottomRightY = 1
    self.cropBottomLeftX = 0
    self.cropBottomLeftY = 1
    self.observations = []
  }

  func setCropCorners(_ corners: [CGPoint]) {
    guard corners.count == 4 else {
      return
    }

    cropTopLeftX = Double(corners[0].x)
    cropTopLeftY = Double(corners[0].y)
    cropTopRightX = Double(corners[1].x)
    cropTopRightY = Double(corners[1].y)
    cropBottomRightX = Double(corners[2].x)
    cropBottomRightY = Double(corners[2].y)
    cropBottomLeftX = Double(corners[3].x)
    cropBottomLeftY = Double(corners[3].y)
  }
}

@Model
final class OCRObservationRecord {
  @Attribute(.unique) var id: UUID
  var text: String
  var confidence: Double
  var boundingBoxX: Double
  var boundingBoxY: Double
  var boundingBoxWidth: Double
  var boundingBoxHeight: Double
  var page: PageRecord?

  init(
    id: UUID = UUID(),
    text: String,
    confidence: Double,
    boundingBoxX: Double,
    boundingBoxY: Double,
    boundingBoxWidth: Double,
    boundingBoxHeight: Double
  ) {
    self.id = id
    self.text = text
    self.confidence = confidence
    self.boundingBoxX = boundingBoxX
    self.boundingBoxY = boundingBoxY
    self.boundingBoxWidth = boundingBoxWidth
    self.boundingBoxHeight = boundingBoxHeight
  }
}

@Model
final class ExtractedTaskRecord {
  @Attribute(.unique) var id: UUID
  var title: String
  var note: String
  var dueStart: Date?
  var dueEnd: Date?
  var isCompleted: Bool
  var lifecycleRaw: String
  var createdAt: Date
  var completedAt: Date?
  var evidenceText: String
  var evidenceObservationID: UUID?
  var calendarEventIdentifier: String?
  var document: DocumentRecord?

  init(
    id: UUID = UUID(),
    title: String,
    note: String = "",
    dueStart: Date? = nil,
    dueEnd: Date? = nil,
    evidenceText: String = "",
    createdAt: Date = .now
  ) {
    self.id = id
    self.title = title
    self.note = note
    self.dueStart = dueStart
    self.dueEnd = dueEnd
    self.evidenceText = evidenceText
    self.createdAt = createdAt
    self.isCompleted = false
    self.lifecycleRaw = TaskLifecycleState.active.rawValue
  }

  var lifecycle: TaskLifecycleState {
    get { TaskLifecycleState(rawValue: lifecycleRaw) ?? .active }
    set { lifecycleRaw = newValue.rawValue }
  }

  var hasCalendarDate: Bool {
    dueStart != nil || dueEnd != nil
  }

  func setCompleted(_ completed: Bool) {
    isCompleted = completed
    lifecycle = completed ? .completed : .active
    completedAt = completed ? .now : nil
  }
}
