-- 008_import_batch_fks.sql
-- Closes the two FK constraints deferred in 005 (contacts) and 006 (projects).
-- The imported_via_batch_id columns were created as bare uuid columns because
-- their target table (import_batches) did not exist yet. 007 built that table;
-- this migration adds the referential constraints, completing the design per
-- Decision 8.
--
-- No columns are added or changed here; only the FK constraints are added.

alter table public.contacts
  add constraint contacts_imported_via_batch_id_fkey
  foreign key (imported_via_batch_id)
  references public.import_batches(id);

alter table public.projects
  add constraint projects_imported_via_batch_id_fkey
  foreign key (imported_via_batch_id)
  references public.import_batches(id);
