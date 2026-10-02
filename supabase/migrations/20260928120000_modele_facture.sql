-- Modèle de facture / devis par défaut de l'atelier
alter table public.ateliers
  add column if not exists modele_facture text not null default 'classique'
  check (modele_facture in ('classique', 'moderne', 'elegant', 'minimal', 'ticket'));
