// ============================================================================
// AgenceRepository.java  -  REPLACE these 4 methods (same names, same params)
//
// WHY: each query is  SELECT [DISTINCT] SUM(...) ... ORDER BY W.Rang_Work
// with NO "group by". Oracle refuses it (ORA-00979 / ORA-01791) -> HTTP 500
// -> the "Total ..." line is missing in the app.
// FIX: remove DISTINCT and ORDER BY (one aggregate row needs neither).
// ============================================================================

// ---- Total arrangement  (typ_work = '0')
@Query(nativeQuery = true, value =
"SELECT nvl(sum(w.jour),0)       AS jour, " +
"       nvl(sum(w.mois),0)       AS mois, " +
"       nvl(sum(w.budg_mois),0)  AS budg_mois, " +
"       nvl(sum(w.annee),0)      AS annee, " +
"       nvl(sum(w.mois_1),0)     AS mois_1, " +
"       nvl(sum(w.budg_annee),0) AS budg_annee, " +
"       nvl(sum(w.annee_1),0)    AS annee_1, " +
"       nvl(sum(w.jour_1),0)     AS jour_1 " +
"FROM WORK_STAT_REV w " +
"WHERE w.cod_hotel = :cod_hotel " +
"  AND typ_work = '0' " +
"  AND Session_Id = :sessionId")
List<GetTotArrengProjection> getDataSetTotArrang(@Param("sessionId") String sessionId,
                                       @Param("cod_hotel") String codHotel);

// ---- Total boissons  (typ_work = '3')
@Query(nativeQuery = true, value =
"SELECT nvl(sum(w.jour),0)       AS sumJour, " +
"       nvl(sum(w.jour_1),0)     AS sumJourUn, " +
"       nvl(sum(w.mois),0)       AS sumMois, " +
"       nvl(sum(w.budg_mois),0)  AS sumBudMois, " +
"       nvl(sum(w.mois_1),0)     AS sumMoisUn, " +
"       nvl(sum(w.annee),0)      AS sumAnne, " +
"       nvl(sum(w.budg_annee),0) AS sumBudAnne, " +
"       nvl(sum(w.annee_1),0)    AS sumAnneUn " +
"FROM WORK_STAT_REV w " +
"WHERE w.cod_hotel = :cod_hotel " +
"  AND typ_work = '3' " +
"  AND Session_Id = :sessionId")
List<GetSetDataBoissTotProjection> getSetBoissTot(
    @Param("sessionId") String sessionId,
    @Param("cod_hotel") String codHotel);

// ---- Total autre  (typ_work = '6')
@Query(nativeQuery = true, value =
"SELECT nvl(sum(w.jour),0)       AS sumJour, " +
"       nvl(sum(w.jour_1),0)     AS sumJourUn, " +
"       nvl(sum(w.mois),0)       AS sumMois, " +
"       nvl(sum(w.budg_mois),0)  AS sumBudMois, " +
"       nvl(sum(w.mois_1),0)     AS sumMoisUn, " +
"       nvl(sum(w.annee),0)      AS sumAnne, " +
"       nvl(sum(w.budg_annee),0) AS sumBudAnne, " +
"       nvl(sum(w.annee_1),0)    AS sumAnneUn " +
"FROM WORK_STAT_REV w " +
"WHERE w.cod_hotel = :cod_hotel " +
"  AND typ_work = '6' " +
"  AND Session_Id = :sessionId")
List<getSetDataAutreTotProjection> getSetDataAutreTot(
    @Param("sessionId") String sessionId,
    @Param("cod_hotel") String codHotel);

// ---- getSetDivers (NOT used by the report screen; it also reads typ_work '3'
//      = boissons by mistake). Same ORDER BY problem, fixed here:
@Query(nativeQuery = true, value =
"SELECT nvl(sum(w.jour),0)       AS sumJour, " +
"       nvl(sum(w.jour_1),0)     AS sumJourUn, " +
"       nvl(sum(w.mois),0)       AS sumMois, " +
"       nvl(sum(w.budg_mois),0)  AS sumBudMois, " +
"       nvl(sum(w.mois_1),0)     AS sumMoisUn, " +
"       nvl(sum(w.annee),0)      AS sumAnne, " +
"       nvl(sum(w.budg_annee),0) AS sumBudAnne, " +
"       nvl(sum(w.annee_1),0)    AS sumAnneUn " +
"FROM WORK_STAT_REV w " +
"WHERE w.cod_hotel = :cod_hotel " +
"  AND typ_work = '4' " +
"  AND Session_Id = :sessionId")
List<GetSetDataDiversProjection> getSetDivers(
    @Param("sessionId") String sessionId,
    @Param("cod_hotel") String codHotel);
