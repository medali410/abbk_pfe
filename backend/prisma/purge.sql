-- Purge Telemetry
DELETE FROM "Telemetry";

-- Purge Models and Machines (Cascade handles Modele3d if configured, or delete explicitly)
DELETE FROM "Modele3d";
DELETE FROM "Machine";

-- Purge Documents
DELETE FROM "Document";

-- Purge Demo Users (Keep admin)
-- Replace 'admin@dali-pfe.com' with the actual admin email if different
DELETE FROM "User" WHERE email NOT IN ('admin@dali-pfe.com');
