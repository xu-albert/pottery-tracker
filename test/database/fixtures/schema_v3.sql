-- Schema version 3 (d5b04df) — version 2 plus the clay_options library,
-- which did not yet have a sort_order column.
CREATE TABLE "pieces" (
  "id" TEXT NOT NULL,
  "title" TEXT NULL,
  "stage" TEXT NULL,
  "clay_type" TEXT NULL,
  "glazes" TEXT NULL,
  "notes" TEXT NULL,
  "cover_photo_id" TEXT NULL,
  "is_archived" INTEGER NOT NULL DEFAULT 0 CHECK ("is_archived" IN (0, 1)),
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
CREATE TABLE "clay_options" (
  "id" TEXT NOT NULL,
  "name" TEXT NOT NULL UNIQUE,
  "created_at" INTEGER NOT NULL,
  PRIMARY KEY ("id")
);
