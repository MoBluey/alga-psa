const { getKnexConfig } = require('../knexfile.cjs');

exports.up = async function(knex) {
  const appUser = process.env.DB_USER_SERVER || 'app_user';
  
  // Explicitly grant permissions on the existing 'tenants' table
  // We use raw SQL because Knex doesn't have a specific method for GRANT
  await knex.raw(`GRANT ALL PRIVILEGES ON TABLE public.tenants TO ${appUser}`);
  
  // Also re-apply default privileges for good measure
  await knex.raw(`ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO ${appUser}`);
  await knex.raw(`ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO ${appUser}`);
  
  console.log(`Explicitly granted permissions on 'tenants' to ${appUser}`);
};

exports.down = async function(knex) {
  // No strict need to revoke in down migration for this fix, 
  // but good practice implies we leave it alone or revoke if strictly needed.
  // Given this is a permission fix for a specific deployment issue, we can leave it empty
  // or optionally revoke.
};
