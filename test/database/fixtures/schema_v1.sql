-- Schema version 1 — a fresh install of the initial Phase 1 release (161ce2a).
-- Fixtures are checked in rather than reconstructed from git so the migration
-- test never depends on clone depth.
CREATE TABLE "pieces" (
  "id" TEXT NOT NULL,
  "title" TEXT NULL,
  "stage" TEXT NULL,
  "clay_type" TEXT NULL,
  "glazes" TEXT NULL,
  "notes" TEXT NULL,
  "cover_photo_id" TEXT NULL,
  "created_at" INTEGER NOT NULL,
  "updated_at" INTEGER NOT NULL,
  PRIMARY KEY ("id")
);
CREATE TABLE "photos" (
  "id" TEXT NOT NULL,
  "piece_id" TEXT NOT NULL REFERENCES pieces (id),
  "local_path" TEXT NOT NULL,
  "thumbnail_path" TEXT NULL,
  "cloud_url" TEXT NULL,
  "date_taken" INTEGER NOT NULL,
  "created_at" INTEGER NOT NULL,
  "sort_order" INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY ("id")
);
