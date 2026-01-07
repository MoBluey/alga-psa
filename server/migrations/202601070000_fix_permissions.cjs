const { getKnexConfig } = require('../knexfile.cjs');

exports.up = async function(knex) {
  // Logic to determine the correct application user to grant permissions to.
  // In some environments (like Coolify migrator), DB_USER_SERVER might incorrectly resolve to 'postgres'.
  let appUser = process.env.DB_USER_SERVER;
  
  if (!appUser || appUser === 'postgres' || appUser === process.env.DB_USER_ADMIN) {
    console.log(`Detected DB_USER_SERVER as '${appUser}', which is likely the admin/migrator user.`);
    console.log("Defaulting to 'app_user' for permission grant target.");
    appUser = 'app_user';
  }

  // Explicitly grant permissions on the existing 'tenants' table
  // We use raw SQL because Knex doesn't have a specific method for GRANT
  try {
    await knex.raw(`GRANT ALL PRIVILEGES ON TABLE public.tenants TO ${appUser}`);
    console.log(`Explicitly granted permissions on 'tenants' to ${appUser}`);
  } catch (error) {
    console.warn(`Failed to grant permissions to ${appUser}: ${error.message}`);
    // Check if we should try quoting the identifier
    try {
      await knex.raw(`GRANT ALL PRIVILEGES ON TABLE public.tenants TO "${appUser}"`);
      console.log(`Explicitly granted permissions on 'tenants' to "${appUser}" (quoted)`);
    } catch (retryError) {
       console.error(`Final failure granting permissions: ${retryError.message}`);
       // Don't throw, as migration should technically complete even if this grant fails (though app might break)
    }
  }
  
  // Also re-apply default privileges for good measure
  try {
    await knex.raw(`ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO ${appUser}`);
    await knex.raw(`ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO ${appUser}`);
    console.log(`Updated default privileges for ${appUser}`);
  } catch (e) {
    console.warn(`Failed to update default privileges: ${e.message}`);
  }
};

exports.down = async function(knex) {
  // No strict need to revoke in down migration for this fix, 
  // but good practice implies we leave it alone or revoke if strictly needed.
  // Given this is a permission fix for a specific deployment issue, we can leave it empty
  // or optionally revoke.
};
