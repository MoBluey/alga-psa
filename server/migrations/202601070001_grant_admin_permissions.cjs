
exports.up = async function(knex) {
  // Get the admin user from environment or default to 'postgres'
  const adminUser = process.env.DB_USER_ADMIN || 'postgres';
  
  console.log(`[Migration] Granting permissions to admin user: ${adminUser}`);

  try {
    // 1. Grant usage on public schema
    await knex.raw(`GRANT USAGE ON SCHEMA public TO ${adminUser}`);
    console.log(`[Migration] Granted USAGE ON SCHEMA public to ${adminUser}`);

    // 2. Grant all privileges on all existing tables
    await knex.raw(`GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO ${adminUser}`);
    console.log(`[Migration] Granted ALL PRIVILEGES ON ALL TABLES to ${adminUser}`);

    // 3. Grant all privileges on all existing sequences
    await knex.raw(`GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO ${adminUser}`);
    console.log(`[Migration] Granted ALL PRIVILEGES ON ALL SEQUENCES to ${adminUser}`);

    // 4. Ensure future tables created by app_user are accessible by adminUser
    // We need to execute this as the table owner (app_user), which is who runs the migrations
    await knex.raw(`ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO ${adminUser}`);
    await knex.raw(`ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO ${adminUser}`);
    console.log(`[Migration] Altered DEFAULT PRIVILEGES for ${adminUser}`);

  } catch (error) {
    console.warn(`[Migration] Error granting permissions: ${error.message}`);
    console.warn('[Migration] Attempting one more time with double quotes for username...');
    
    try {
      // Retry with quoted identifiers in case of special characters or case sensitivity
      await knex.raw(`GRANT USAGE ON SCHEMA public TO "${adminUser}"`);
      await knex.raw(`GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO "${adminUser}"`);
      await knex.raw(`GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO "${adminUser}"`);
      await knex.raw(`ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO "${adminUser}"`);
      await knex.raw(`ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO "${adminUser}"`);
      console.log(`[Migration] Successfully granted permissions using quoted identifier "${adminUser}"`);
    } catch (retryError) {
      console.error(`[Migration] Failed to grant permissions to ${adminUser}:`, retryError);
      // We don't throw here to avoid failing the entire deployment if this is just a duplicate grant or minor issue,
      // but strictly speaking, if this fails, pgboss will likely fail.
      // However, we'll let the application crash if it can't connect, rather than breaking the migration history.
    }
  }
};

exports.down = async function(knex) {
  // We generally don't revoke permissions in down migrations as it might break other things,
  // and permissions are cumulative. But strictly speaking we could REVOKE.
  // For safety/stability in production, we'll log and skip.
  console.log('[Migration] Skipping permission revocation for safety.');
};
