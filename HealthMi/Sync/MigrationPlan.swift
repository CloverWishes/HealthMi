import Foundation
import SwiftData

/// 当前 Schema 版本（v1）。
/// 未来 schema 变更时新建 SchemaV2 并在 MigrationPlan 中添加迁移阶段。
enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [SyncState.self, StressRecord.self, SyncLogEntry.self]
    }
}

/// 迁移计划。目前只有 v1，无迁移阶段。
/// 当 schema 变更时：新建 SchemaV2 → 在 stages 中添加 `.lightweight` 或 `.custom` 迁移。
enum MigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self]
    }
    static var stages: [MigrationStage] { [] }
}
