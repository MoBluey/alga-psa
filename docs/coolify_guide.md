# Alga PSA - Coolify Deployment Guide

This guide details the steps to deploy Alga PSA (Enterprise Edition with SSO) on Coolify using the `fix/coolify-deployment` branch.

## 1. Prerequisites

*   A **Coolify** instance (v4+ recommended).
*   A **Postgres Database** (External or deployed via Coolify) - *Optional if using the built-in docker-compose postgres.*
*   A **Redis** instance - *Optional if using the built-in docker-compose redis.*
*   **SSO Credentials:**
    *   Google OAuth Client ID & Secret
    *   Microsoft Azure AD Client ID, Secret, & Tenant ID
*   **Generate Random Secrets** (32+ chars) for:
    *   `NEXTAUTH_SECRET`
    *   `ALGA_AUTH_KEY`
    *   `CRYPTO_KEY`

## 2. Project Setup in Coolify

1.  **Create New Resource:**
    *   Select **Source**: Git Repository (Public or Private).
    *   **Repository URL:** `https://github.com/MoBluey/alga-psa` (or your private repo URL).
    *   **Branch:** `fix/coolify-deployment` (or `main` if merged).
    *   **Build Pack:** Select **Docker Compose**.

2.  **Configuration:**
    *   **Docker Compose File:** Paste the content of `docker-compose-unified.yaml` (from the repo root).
        *   *Note: This file handles the entire stack: App, Postgres, Redis, Migrations, and Init scripts.*

3.  **Build Settings:**
    *   Ensure the **Base Directory** is set to `/` (repository root).

## 3. Environment Variables

Configure the following variables in the **Environment Variables** tab of your Coolify resource.

### Core & Database
| Variable | Value / Notes |
| :--- | :--- |
| `APP_NAME` | `Alga PSA` |
| `APP_ENV` | `production` |
| `NODE_ENV` | `production` |
| `NEXT_PUBLIC_EDITION` | `enterprise` (Enables SSO features) |
| `POSTGRES_PASSWORD` | **[SECURE]** Superuser password for the database. |
| `DB_PASSWORD_SERVER` | **[SECURE]** Password for `app_user` (can be same as above or unique). |
| `DB_HOST` | `postgres` (internal service name) |
| `DB_PORT` | `5432` |
| `DB_NAME_SERVER` | `server` |
| `DB_USER_SERVER` | `app_user` (Managed by `init-db` service) |
| `REDIS_PASSWORD` | **[SECURE]** Password for Redis. |

### Authentication & Security
| Variable | Value / Notes |
| :--- | :--- |
| `NEXTAUTH_URL` | `https://psa.your-domain.com` (Your actual Coolify URL) |
| `NEXTAUTH_SECRET` | **[SECURE]** Random 32-char string (e.g. `openssl rand -base64 32`) |
| `ALGA_AUTH_KEY` | **[SECURE]** Random 32-char string |
| `CRYPTO_KEY` | **[SECURE]** Random 32-char string |

### Single Sign-On (SSO)
| Variable | Value / Notes |
| :--- | :--- |
| `GOOGLE_OAUTH_CLIENT_ID` | From Google Cloud Console |
| `GOOGLE_OAUTH_CLIENT_SECRET` | **[SECURE]** From Google Cloud Console |
| `MICROSOFT_OAUTH_CLIENT_ID` | From Azure Portal |
| `MICROSOFT_OAUTH_CLIENT_SECRET` | **[SECURE]** From Azure Portal |
| `MICROSOFT_OAUTH_TENANT_ID` | From Azure Portal |

### Email (Optional - SMTP)
To enable email sending, set `EMAIL_ENABLE=true` and provide:
*   `EMAIL_HOST`, `EMAIL_PORT`, `EMAIL_USERNAME`, `EMAIL_PASSWORD`, `EMAIL_FROM`.

## 4. Deployment Steps

1.  **Save** all Environment Variables.
2.  Click **Deploy** in Coolify.
3.  **Monitor Logs:**
    *   Watch the build logs to ensure `Dockerfile.build` executes correctly.
    *   Watch the **Deployment Logs**:
        *   `postgres` service should start first.
        *   `init-db` service should run, create `app_user`, and exit with "Database initialization complete."
        *   `migrator` service should run `knex migrate:latest` and exit successfully.
        *   `app` service should start and listen on port 3000.

## 5. Post-Deployment Verification

1.  **Access the URL:** Open your deployed domain (e.g., `https://psa.your-domain.com`).
2.  **Register First Admin:**
    *   Go to `/auth/register`.
    *   Create an account. *The "null tenant" bug should be fixed, creating both Tenant and User successfully.*
3.  **Test SSO:**
    *   Logout.
    *   On the login page, verify "Sign in with Google" or "Sign in with Microsoft" buttons appear.
    *   Attempt an SSO login.

## 6. Troubleshooting

*   **"Relation 'users' does not exist":** The `migrator` service failed or didn't run. Check logs for `migrator`.
*   **"Password authentication failed":** Verify `POSTGRES_PASSWORD` and `DB_PASSWORD_SERVER` match what is in the Coolify environment variables. Restart the `init-db` service or wipe the `postgres-data-fresh-v2` volume to force a reset.
*   **"Null value in column tenant":** Ensure you are deploying the `fix/coolify-deployment` branch which contains the patch for `useRegister.tsx`.
*   **"Command failed with exit code 1" / "SIGKILL" during build:** This usually means the server ran out of memory. We have reduced the build memory limit to 2GB in `Dockerfile.build`. If it still fails, consider enabling **Swap Memory** on your implementation server or temporarily stopping other services during the first build.

