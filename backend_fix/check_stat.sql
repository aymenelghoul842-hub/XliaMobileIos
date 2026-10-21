-- ============================================================================
-- Run in SQL Developer on the hotel schema (APP_MOBILE).
-- :sid  = IN6_session_  shown in the app (chip "x/14" -> first box)
-- :cod  = IN8_cod_hotel_ shown in the same box
-- ============================================================================

-- 1) FIRST CHECK: did the procedure write rows for this session?
--    typ_work 0 = arrangement, 1 = logement, 2 = nourriture, 3 = boissons,
--    4 = divers, 6 = autre, 9 = extra.   No row = procedure wrote nothing.
select typ_work, count(*) nb
  from work_stat_rev
 where session_id = :sid
   and cod_hotel  = :cod
 group by typ_work
 order by typ_work;

-- 2) Statistics lines (Nuitees clients ... Chambres offertes)
select count(*) nb_stat_lines
  from work_stat
 where session_id = :sid
   and cod_hotel  = :cod;

-- 3) Rows written under ANOTHER session id (procedure ignored IN6_session_)
select session_id, cod_hotel, count(*) nb
  from work_stat_rev
 group by session_id, cod_hotel
 order by nb desc;

-- 4) The detail lines exactly as the app reads them (logement example)
select cod_work, lib_work, jour, jour_1, mois, budg_mois, mois_1,
       annee, budg_annee, annee_1
  from work_stat_rev
 where session_id = :sid
   and cod_hotel  = :cod
   and typ_work   = '1'
 order by rang_work;

-- 5) Last day already consolidated (IN1_date_purge_)
select max(jour) as stat_real from stat_real where cod_hotel = :cod;
