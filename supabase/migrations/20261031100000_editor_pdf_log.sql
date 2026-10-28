-- Editor PDF: registro delle operazioni in log_attivita, come negli altri moduli.
-- Le tabelle pdf_* sono state create a mano con 01_editor_pdf.sql
-- (copia identica in 20261031090000_editor_pdf.sql).
-- pdf_audit non ha il trigger: è già esso stesso un registro (solo aggiunta).
begin;

drop trigger if exists trg_log_attivita on public.pdf_modelli;
create trigger trg_log_attivita after insert or update or delete on public.pdf_modelli
  for each row execute function public.fn_log_attivita();

drop trigger if exists trg_log_attivita on public.pdf_documenti;
create trigger trg_log_attivita after insert or update or delete on public.pdf_documenti
  for each row execute function public.fn_log_attivita();

commit;
