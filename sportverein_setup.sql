-- =====================================================================
--  Sportverein-Datenbank ("hhdemodb") für PostgreSQL
--  Passend zu den Übungsblöcken 1–10 im Skript "Grundlagen Datenbanksysteme"
--  (Prof. Dr. Sandbrink, DHBW Mannheim, WS 2026/27, Folien ab S. 242)
--
--  Tabellen laut ER-Modell (Folie 242):
--    ABTEILUNGEN, MITGLIEDER, ALTERSGRUPPEN, BEITRAGSSATZE
--
--  WICHTIG: Die Originaldaten des Professors sind im Skript nur
--  ausschnittweise abgedruckt. Die Daten hier sind so rekonstruiert,
--  dass die auf den Folien gezeigten Ergebnisse herauskommen
--  (Aufgabe 1.2, 1.4, 1.5, 3.6, 4.8, 5.4, 8.2, 8.4 ...). Mitglieder, die
--  auf den Folien nicht vorkommen, sind ergänzt. Wenn ihr die echte
--  hhdemodb (z. B. über Moodle) bekommt, nehmt die.
--
--  Datenstand wie auf den Folien (ca. 2016). Für altersabhängige
--  Abfragen (z. B. 5.7 B-Jugend) statt CURRENT_DATE einen Stichtag wie
--  DATE '2016-10-01' verwenden, sonst sind heute alle "Erwachsene".
--
--  Ausführen (Datenbank vorher anlegen, siehe Anleitung):
--    psql -U postgres -d sportverein -f sportverein_setup.sql
--  oder in pgAdmin/DBeaver: Query Tool auf DB "sportverein" öffnen,
--  Datei laden, komplett ausführen.
--
--  Das Skript kann jederzeit erneut ausgeführt werden, um alles auf
--  den Ausgangszustand zurückzusetzen.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 0) Datumsformat wie im Skript (TT.MM.JJJJ), damit Literale wie
--    '01.01.1990' oder '13.05.14' aus den Lösungen funktionieren.
-- ---------------------------------------------------------------------
SET datestyle = 'German, DMY';

DO $$
BEGIN
  EXECUTE format('ALTER DATABASE %I SET datestyle = %L',
                 current_database(), 'German, DMY');
EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE 'Konnte datestyle nicht dauerhaft setzen (keine Rechte) – '
               'gilt nur für diese Sitzung.';
END $$;


-- ---------------------------------------------------------------------
-- 1) Aufräumen (auch Objekte, die in den Übungen selbst angelegt werden)
-- ---------------------------------------------------------------------
DROP VIEW  IF EXISTS mi_liste, neu_mi, neu_mi_constr CASCADE;
DROP TABLE IF EXISTS fbentry, kfz, fahrtenbuch, fb CASCADE;
DROP TABLE IF EXISTS beitragssatze, mitglieder, altersgruppen, abteilungen CASCADE;


-- ---------------------------------------------------------------------
-- 2) Tabellen
--    Oracle -> PostgreSQL:  VARCHAR2 -> VARCHAR,  NUMBER(38) -> INTEGER,
--                           NUMBER(4,2) -> NUMERIC(4,2)
-- ---------------------------------------------------------------------
CREATE TABLE abteilungen (
    abt_nr   INTEGER      PRIMARY KEY,
    abt_bez  VARCHAR(30)
);

CREATE TABLE mitglieder (
    mi_nr         INTEGER      NOT NULL PRIMARY KEY,
    abt_nr        INTEGER      NOT NULL,      -- bewusst OHNE Fremdschlüssel,
                                              -- siehe Übung 8.6–8.8
    mit_koord     INTEGER      REFERENCES mitglieder(mi_nr),
    mi_name       VARCHAR(30),
    mi_vname      VARCHAR(30),
    mi_gebdatum   DATE,
    mi_seit       DATE,
    mi_aufent     INTEGER,                    -- Aufwandsentschädigung
    mi_beitr_akt  NUMERIC(4,2)                -- aktueller Beitrag
);

CREATE TABLE altersgruppen (
    gr_nr        INTEGER      PRIMARY KEY,
    gr_bez       VARCHAR(30),
    gr_altervon  INTEGER,
    gr_alterbis  INTEGER
);

-- Schwache Entität "Beitragssätze" (Name wie in der Lösung zu 3.1)
CREATE TABLE beitragssatze (
    gr_nr      INTEGER      NOT NULL REFERENCES altersgruppen(gr_nr),
    bs_nr      INTEGER      NOT NULL,
    bs_ab      DATE,
    bs_bis     DATE,                          -- NULL = gilt bis heute
    bs_betrag  NUMERIC(4,2),
    PRIMARY KEY (gr_nr, bs_nr)
);


-- ---------------------------------------------------------------------
-- 3) Daten
-- ---------------------------------------------------------------------
INSERT INTO abteilungen VALUES
  (1, 'Kegeln'),
  (2, 'Bowling'),
  (3, 'Turnen'),
  (4, 'Verwaltung'),
  (5, 'Schwimmen');          -- hat keine Mitglieder (vgl. Hinweis zu 5.6)
                             -- Abteilung 6 fehlt absichtlich (Übung 8.7/8.8)

INSERT INTO altersgruppen VALUES
  (1, 'Erwachsene', 18, 150),
  (2, 'B-Jugend',   15,  18),
  (3, 'C-Jugend',   13,  14),
  (4, 'D-Jugend',   12,  12),
  (5, 'E-Jugend',   10,  11),
  (6, 'F-Jugend',    0,   9);

INSERT INTO beitragssatze VALUES
  (1, 1, '01.01.2005', '31.12.2010', 25.00),
  (1, 2, '01.01.2011', NULL,         30.00),
  (2, 1, '01.01.2005', '31.12.2010', 12.00),
  (2, 2, '01.01.2011', NULL,         15.00),
  (3, 1, '01.01.2005', '31.12.2010', 10.00),
  (3, 2, '01.01.2011', NULL,         12.50),
  (4, 1, '01.01.2005', '31.12.2010',  8.00),
  (4, 2, '01.01.2011', NULL,          9.00),
  (5, 1, '01.01.2005', '31.12.2010',  6.00),
  (5, 2, '01.01.2011', NULL,          7.50),
  (6, 1, '01.01.2005', '31.12.2010',  4.00),
  (6, 2, '01.01.2011', NULL,          6.00);

-- Spaltenreihenfolge wie in Aufgabe 1.1 / 8.4:
-- mi_nr, abt_nr, mit_koord, mi_name, mi_vname, mi_gebdatum, mi_seit, mi_aufent, mi_beitr_akt
-- (Reihenfolge der INSERTs folgt der Koordinations-Hierarchie)

-- Vereinsvorsitzender (wird von niemandem koordiniert)
INSERT INTO mitglieder VALUES
  (121, 4, NULL, 'Meller',  'Peter',  '24.08.1963', '01.03.1992', 230, 25.00);

-- Abteilungsleitungen / Vorstand
INSERT INTO mitglieder VALUES
  ( 65, 1, 121, 'Kappes',  'Helga',  '03.11.1958', '01.02.1979',  90, 30.00),
  ( 12, 2, 121, 'Carnot',  'France', '03.07.1979', '01.09.1997', 120, 35.00),
  ( 57, 3, 121, 'Fluck',   'Sigrid', '08.03.1965', '01.01.1984', 150, 20.00),
  ( 88, 4, 121, 'Berbes',  'Jens',   '27.07.1981', '15.06.2003', 260, 25.00),
  ( 51, 4, 121, 'Holter',  'Burgi',  '15.06.1988', '01.04.1996', NULL, 20.00);

-- Abteilung 1: Kegeln
INSERT INTO mitglieder VALUES
  ( 83, 1,  65, 'Lering',  'Paul',   '01.04.1974', '15.01.1995',  60, 30.00),
  ( 39, 1,  83, 'Jerres',  'Jenny',  '15.02.1983', '01.05.2006', NULL, 30.00),
  ( 31, 1,  65, 'Krupp',   'Karla',  '17.03.1978', '01.10.1993', NULL, 30.00),
  ( 33, 1,  83, 'Krapp',   'Theo',   '10.10.1986', '01.01.1999', NULL, 30.00),
  (108, 1,  65, 'Zander',  'Alois',  '07.08.1974', '01.05.1990', NULL, 30.00),
  ( 71, 1,  65, 'Popich',  'Harry',  '04.01.1976', '01.03.1994',  40, 30.00),
  (104, 1,  65, 'Wolff',   'Dieter', '12.05.1949', '01.04.1971', NULL, 30.00),
  ( 17, 1,  65, 'Haas',    'Gerda',  '30.09.1952', '01.10.1978', NULL, 30.00),
  ( 27, 1,  65, 'Kuhn',    'Otto',   '21.01.1945', '15.03.1968', NULL, 15.00),
  ( 52, 1,  65, 'Lorenz',  'Maria',  '06.06.1961', '01.07.1985', NULL, 30.00);

-- Abteilung 2: Bowling
INSERT INTO mitglieder VALUES
  (  3, 2,  12, 'Adomit',  'Karl',   '31.07.1980', '01.02.1998', NULL, 35.00),
  ( 46, 2,  12, 'Hirth',   'Simone', '14.04.1984', '01.06.2000', NULL, 35.00),
  ( 74, 2,  12, 'Rack',    'Tim',    '15.07.1985', '01.11.1999', NULL, 35.00),
  ( 23, 2,  12, 'Remsen',  'Jorge',  '07.07.1990', '01.03.2005', 130, 35.00),
  ( 47, 2,  23, 'Hoff',    'Lena',   '20.02.2000', '15.01.2001', NULL,  8.50),
  (110, 2,  12, 'Vogt',    'Hans',   '01.12.1955', '01.01.1980', NULL, 35.00),
  ( 90, 2,  12, 'Schulz',  'Rita',   '22.04.1968', '01.09.1989', NULL, 35.00);

-- Abteilung 3: Turnen (genau 9 Mitglieder, vgl. 4.8 und 8.2)
INSERT INTO mitglieder VALUES
  ( 76, 3,  57, 'Ruppel',  'Hilda',  '19.10.1959', '01.05.1981',  50, 20.00),
  ( 19, 3,  57, 'Dierks',  'Benn',   '11.02.1971', '01.04.1988', NULL, 20.00),
  ( 22, 3,  57, 'Engels',  'Bruno',  '30.08.1950', '01.09.1975', NULL, 20.00),
  (101, 3,  76, 'Traut',   'Jenny',  '27.03.1999', '01.09.2000', NULL,  9.00),
  ( 86, 3,  76, 'Brutt',   'Jasmin', '12.12.2003', '15.01.2008', NULL,  7.50),
  ( 95, 3,  76, 'Brahms',  'Steffi', '04.04.2005', '01.09.2010', NULL,  7.50),
  (125, 3,  76, 'Mahn',    'Willy',  '23.05.2007', '01.02.2013', NULL,  6.00),
  ( 79, 3,  76, 'Eckel',   'Bernd',  '17.08.2007', '01.04.2014', NULL,  6.00);

-- Abteilung 4: Verwaltung (weitere)
INSERT INTO mitglieder VALUES
  ( 44, 4,  88, 'Renzer',  'Lisa',   '13.05.1994', '01.09.2012',  30, 25.00),
  (102, 4,  88, 'Simons',  'Terry',  '12.12.1990', '01.08.1998',  90, 20.00);


-- ---------------------------------------------------------------------
-- 4) OPTIONAL: kleine Oracle-Kompatibilität
--    Damit laufen viele Musterlösungen fast unverändert:
--      SELECT ... FROM dual;   NVL(a, b);   TO_CHAR(zahl);
--      MONTHS_BETWEEN(d1, d2)
--    SYSDATE gibt es trotzdem nicht -> CURRENT_DATE schreiben.
--    Wer lieber "reines" PostgreSQL übt: diesen Abschnitt löschen.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW dual AS SELECT 'X'::varchar(1) AS dummy;

CREATE OR REPLACE FUNCTION nvl(anyelement, anyelement)
RETURNS anyelement LANGUAGE sql IMMUTABLE AS
$$ SELECT COALESCE($1, $2) $$;

CREATE OR REPLACE FUNCTION to_char(numeric)
RETURNS text LANGUAGE sql IMMUTABLE AS
$$ SELECT $1::text $$;

CREATE OR REPLACE FUNCTION months_between(d1 date, d2 date)
RETURNS numeric LANGUAGE sql IMMUTABLE AS
$$ SELECT (EXTRACT(YEAR  FROM age(d1, d2)) * 12
         + EXTRACT(MONTH FROM age(d1, d2))
         + EXTRACT(DAY   FROM age(d1, d2)) / 31.0)::numeric $$;


-- ---------------------------------------------------------------------
-- 5) Kontrolle
-- ---------------------------------------------------------------------
SELECT 'abteilungen'   AS tabelle, COUNT(*) AS zeilen FROM abteilungen
UNION ALL SELECT 'mitglieder',    COUNT(*) FROM mitglieder
UNION ALL SELECT 'altersgruppen', COUNT(*) FROM altersgruppen
UNION ALL SELECT 'beitragssatze', COUNT(*) FROM beitragssatze;
