-- Schema version 6 (989cad3) — version 5 plus the tag library, its junction
-- table and the denormalized pieces.tags column. tag_options has no `color`
-- here: that column arrived in version 7. The first version that upgraded
-- cleanly before this fix.
CREATE TABLE "pieces" (
  "id" TEXT NOT NULL,
  "title" TEXT NULL,
  "stage" TEXT NULL,
  "clay_type" TEXT NULL,
  "glazes" TEXT NULL,
  "tags" TEXT NULL,
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
  "sort_order" INTEGER NOT NULL DEFAULT 0,
  "created_at" INTEGER NOT NULL,
  PRIMARY KEY ("id")
);
CREATE TABLE "glaze_options" (
  "id" TEXT NOT NULL,
  "name" TEXT NOT NULL UNIQUE,
  "sort_order" INTEGER NOT NULL DEFAULT 0,
  "created_at" INTEGER NOT NULL,
  PRIMARY KEY ("id")
);
CREATE TABLE "piece_glazes" (
  "id" TEXT NOT NULL,
  "piece_id" TEXT NOT NULL,
  "glaze_option_id" TEXT NOT NULL,
  "sort_order" INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY ("id")
);
CREATE TABLE "tag_options" (
  "id" TEXT NOT NULL,
  "name" TEXT NOT NULL UNIQUE,
  "sort_order" INTEGER NOT NULL DEFAULT 0,
  "created_at" INTEGER NOT NULL,
  PRIMARY KEY ("id")
);
CREATE TABLE "piece_tags" (
  "id" TEXT NOT NULL,
  "piece_id" TEXT NOT NULL,
  "tag_option_id" TEXT NOT NULL,
  PRIMARY KEY ("id")
);
