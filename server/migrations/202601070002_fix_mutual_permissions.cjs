
exports.up = async function(knex) {
  const adminUser = process.env.DB_USER_ADMIN || 'postgres';
  const appUser = process.env.DB_USER_SERVER || 'app_user';

  console.log(`[Migration] Fixing mutual permissions between admin (${adminUser}) and app (${appUser})`);

  // Helper to grant permissions to a user
  const grantToUser = async (user) => {
    try {
      console.log(`[Migration] Granting permissions to ${user}...`);
      await knex.raw(`GRANT USAGE ON SCHEMA public TO "${user}"`);
      await knex.raw(`GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO "${user}"`);
      await knex.raw(`GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO "${user}"`);
      // Ensure future tables created by the CURRENT user are accessible to THIS user (reflexive, but good practice)
      // Note: ALTER DEFAULT PRIVILEGES applies to objects created by the USER EXECUTING THE COMMAND.
      // So if this runs as postgres, we can grant access to app_user for future postgres tables.
      console.log(`[Migration] Successfully granted standard permissions to ${user}`);
    } catch (error) {
      // Try again without quotes just in case, or log specific error
      try {
        await knex.raw(`GRANT USAGE ON SCHEMA public TO ${user}`);
        await knex.raw(`GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO ${user}`);
        await knex.raw(`GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO ${user}`);
        console.log(`[Migration] Successfully granted standard permissions to ${user} (unquoted)`);
      } catch (retryError) {
        console.warn(`[Migration] Failed to grant permissions to ${user}: ${retryError.message}`);
      }
    }
  };

  // 1. Grant everything to app_user (Critical fix)
  if (appUser !== adminUser) {
    await grantToUser(appUser);
  }

  // 2. Grant everything to admin_user (Safety net)
  await grantToUser(adminUser);

  // 3. Fix Future Permissions (The "Mutual" part)
  // We need to ensure that tables created by the current user (migrator) are accessible to the app user.
  // We assume the current connection is the migrator (admin/postgres).
  try {
    console.log(`[Migration] Altering default privileges for tables created by current user to be accessible by ${appUser}...`);
    await knex.raw(`ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO "${appUser}"`);
    await knex.raw(`ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO "${appUser}"`);
    console.log(`[Migration] Success: Future tables created by migrator will be accessible to ${appUser}`);
  } catch (error) {
    try {
        await knex.raw(`ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO ${appUser}`);
        await knex.raw(`ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO ${appUser}`);
        console.log(`[Migration] Success: Future tables created by migrator will be accessible to ${appUser} (unquoted)`);
    } catch (retryError) {
        console.warn(`[Migration] Failed to alter default privileges for ${appUser}: ${retryError.message}`);
    }
  }
};

exports.down = async function(knex) {
  console.log('[Migration] Skipping permission revocation for safety.');
};
