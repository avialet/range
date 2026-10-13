import Foundation
import GRDB

/// Schema de la base. Une migration par version du schema, jamais modifiee
/// une fois publiee : on en ajoute une nouvelle (`v2`, `v3`...).
enum Migrations {
    static var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()
        #if DEBUG
        m.eraseDatabaseOnSchemaChange = true
        #endif

        m.registerMigration("v1") { db in
            try db.create(table: "meta") { t in
                t.primaryKey("key", .text)
                t.column("value", .text).notNull()
            }
            // Lots : une passe ou un clic « Ranger » = un lot, defait d'un coup.
            try db.create(table: "batch") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("date", .datetime).notNull()
                t.column("trigger", .text).notNull()
                t.column("undoneAt", .datetime)
            }
            // Un fichier range : d'ou il vient, ou il est, de quoi verifier que c'est bien lui.
            try db.create(table: "move") { t in
                t.autoIncrementedPrimaryKey("id")
                t.belongsTo("batch", onDelete: .cascade).notNull()
                t.column("date", .datetime).notNull()
                t.column("source", .text).notNull()
                t.column("destination", .text).notNull()
                t.column("kind", .text).notNull()
                t.column("ruleId", .text).notNull()
                t.column("reason", .text)
                t.column("inode", .integer).notNull()
                t.column("size", .integer).notNull()
                t.column("isDirectory", .boolean).notNull()
                t.column("createdDirs", .text).notNull()
                t.column("undoneAt", .datetime)
                t.column("restoredTo", .text)
            }
            try db.create(index: "move_on_date", on: "move", columns: ["date"])
            // Regles de l'utilisateur, dans l'ordre (JSON de `Rule`).
            try db.create(table: "rule") { t in
                t.primaryKey("id", .text)
                t.column("position", .integer).notNull()
                t.column("json", .text).notNull()
            }
            // Fichiers remis en place a la main : Range les laisse tranquilles.
            try db.create(table: "held") { t in
                t.primaryKey("inode", .integer)
                t.column("path", .text).notNull()
                t.column("date", .datetime).notNull()
            }
        }

        // v2 : journal ecrit avant d'agir (etat `pending` puis `done`), raison d'un echec d'annulation.
        m.registerMigration("v2") { db in
            try db.alter(table: "move") { t in
                t.add(column: "state", .text).notNull().defaults(to: "done")
                t.add(column: "undoError", .text)
            }
        }

        return m
    }
}
