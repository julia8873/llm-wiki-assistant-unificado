# LLM Wiki Assistant (Unified Ecosystem)

This repository unifies the complete teaching and analytics environment, combining **Moodle + Matrix + Git** integrations with the AI interaction traceability and metrics system.

---

## Project Structure

The project is designed around a microservices architecture. Below is a description of each main directory:

### Root
- **`docker-compose.yml`**: Central orchestrator file that defines and starts all microservices together (Databases, APIs, Bots, Frontend, etc.).
- **`.env.example`**: Environment variables template where passwords, tokens and sensitive configuration for the entire ecosystem are defined.
- **`instalar.sh`**: Interactive script to facilitate installation and execution of testing/documentation tools.

### Global Directories
- **`config/`**: Contains `config.yaml`, which acts as the single source of truth for non-sensitive configuration (LLM providers to use, Git repository configuration, etc.).
- **`docs/`**: Detailed technical documentation and diagrams.
- **`scripts/`**: Auxiliary scripts (such as database dump tools).
- **`tests/`**: Consolidated automated test suite for the entire system.

### Source Code (`src/`)
Contains the different microservices:

* **Core Services (Base Infrastructure)**
  * **`moodle/`**: Moodle code and configuration, including the custom plugin (`block_bdc`) that intercepts logins to sync users.
  * **`matrix/`**: Synapse (Matrix server) and Element (web chat client) configuration.
  * **`bot/`**: Source code for *Maubot* (the Matrix chat bot) and the *sync-workers* responsible for syncing material with GitHub in the background.
  * **`api/` (mapeo-api)**: Bridge API responsible for maintaining the central user mapping (Student <-> Git <-> Matrix).
  * **`shared/`**: Python packages and libraries shared between multiple services to avoid code duplication.
  * **`backup/`**: Microservice with a Cron job that performs database backups.

* **Traceability Services (Analytics & Metrics)**
  * **`metrics-api/`**: API dedicated to collecting, consolidating and exposing student AI interaction events and the pedagogical catalogue.
  * **`metrics-worker/`**: Background process that audits Git repositories for discrepancies or new interactions and stores them in the DB.
  * **`frontend/`**: Visual dashboard built in React/Vite for teachers to review student metrics.

---

## Step-by-Step Installation Guide

To deploy the ecosystem from scratch, you have two approaches: use the automatic assistant or do it manually.

### Option A: Automated Installation (Recommended)
The `./instalar.sh` script is an orchestrator that generates templates, packages the code and starts the environment step by step.

1. **Clone and Enter:**
   ```bash
   cd llm-wiki-assistant-unificado
   ```
2. **Auto-generate base files:**
   Run the orchestrator without arguments:
   ```bash
   ./instalar.sh
   ```
   *The script will detect that configuration files are missing, automatically copy `.env` and `config/config.yaml` from their `.example` templates, and stop notifying you to fill them in.*
3. **Fill in Secrets and Configuration:**
   - Open the newly created `.env` file and change all passwords marked as `CHANGE_ME`.
      You will need to generate the following variables with `openssl rand -hex 32`:
      - AGENT_HMAC_SECRET
      - INTERNAL_SERVICE_TOKEN
      - PII_SECRET_KEY
      - MAUBOT_CRYPTO_PICKLE_KEY
   - Open `config/config.yaml`. Set your `git.proveedor_activo` (e.g. github) and enter your organisation and PAT. **Important for GitHub:** The classic token must have the full **`repo`** scope checked.
   - In the same file, set your `llm.proveedor_activo`.
   - **If using Ollama via SSH tunnel**, set `ollama.api_base_url` to `http://host.docker.internal:11434/v1` (the port must match your local tunnel port).
4. **Start Infrastructure and Package:**
   Run the orchestrator again:
   ```bash
   ./instalar.sh
   ```

---

### Option B: Quick Manual Start (Docker only)
If you prefer to do it manually, or just want to start/restart the stack:
1. Copy the files manually:
   ```bash
   cp .env.example .env
   cp config/config.yaml.example config/config.yaml
   ```
2. Fill them in with your data and secrets.
3. Start the containers using the shortcut:
   ```bash
   ./instalar.sh up
   ```
   *(Note: `instalar.sh up` reads your `config.yaml`, generates the final variables and runs `docker compose up -d` for you. It does not generate documentation or package the bot. If you use this option, you will need to generate the bot later with `./instalar.sh bot package`).*

---

### Step 5: Post-Installation Operations

Once the containers are running (you can verify with `docker ps`), you need to link the bot:

1. **Matrix Token:** Open the chat interface (Element) at `http://localhost:8081`, log in as `admin` with the Synapse password. Go to *Settings -> Help & About -> Advanced* and copy your **Access Token**. Paste it into your `.env` file under the variable `MATRIX_ACCESS_TOKEN`.
2. **Restart Moodle:** Since Moodle needs that token, apply the changes by restarting it:
   ```bash
   docker compose restart moodle
   ```
3. **Configure the Bot (Maubot):**
   - *Note:* If you used "Option B" in Step 4, first compile the bot by running `./instalar.sh bot package` to get the `.mbp` file. If you used "Option A", it is already ready.
   - Access the admin interface at `http://localhost:29317/_matrix/maubot/` (user `admin`, password from your `.env`).
   - Upload the bot plugin (packaged as `.mbp`) in the **Plugins** tab; it will be located at: `llm-wiki-assistant-unificado/src/bot/llm-wiki-assistant-plugin/plugin.mbp`.
   - Add the client connecting it to `http://synapse:8008` (using the user `@llm_wiki_bot:localhost`).
   The bot access token is in your `.env` under the variable `BOT_ACCESS_TOKEN`, generated after running `./instalar.sh`.
   - Create the instance by linking the Client and the Plugin.

---

### Step 5b: Enable Moodle Web Services

The metrics dashboard authenticates users via Moodle REST API. This must be enabled manually after the first start:

1. Log into Moodle at `http://localhost:8000` as `admin`.
2. Go to **Site administration -> Advanced features** and enable **Enable web services**.
3. Go to **Site administration -> Plugins -> Web services -> External services** and make sure `moodle_mobile_app` is enabled.
4. Go to **Site administration -> Plugins -> Web services -> Manage protocols** and enable the **REST** protocol.

Once done, users will be able to log into the metrics dashboard at `http://localhost:3001`.

---

## Step 6: Creating Users (Teachers and Students)

After a reset, the Moodle database is empty. You must create users from scratch. The full flow has three parts: create the user in Moodle, provision their GitHub repository, and register the mapping in the system.

### 6.1 Create the Official Course Repository (once per course)

Before creating students, the teacher must provision the master course repository on GitHub. This creates the `<CourseName>-Oficial` repo from the `BdC-template` template and adds the teacher as a collaborator with maintain permissions.

```bash
./instalar.sh git <CourseName> <teacher_github_username>
```

Example:
```bash
./instalar.sh git BdC2024 julia8873
```

> Warning: This command requires `config/config.yaml` to have a correctly configured GitHub `pat` with the full `repo` scope.

---

### 6.2 Create a Teacher in Moodle

1. Log into Moodle at `http://localhost:8000` as `admin`.
2. Go to **Site administration -> Users -> Accounts -> Add a new user**.
3. Fill in the required fields:
   - **Username**: e.g. `profesor1`
   - **Password**, **Email**, **First name**, **Last name**
4. Save the user.
5. Assign the teacher role in the course:
   - Go to the course -> **Participants -> Enrol users**.
   - Search for the user and assign the **Teacher** role.

---

### 6.3 Create a Student in Moodle

1. Follow the same process as for the teacher (**Site administration -> Users -> Accounts -> Add a new user**).
2. When enrolling them in the course, assign the **Student** role.

---

### 6.4 Register the User <-> GitHub <-> Matrix Mapping

The system needs to know which GitHub repository and which Matrix room correspond to each student. Once the student logs into Moodle **for the first time**, the `block_bdc` plugin creates the mapping automatically.

If you need to register it manually, you can do so with a direct API call (the value of `MAPEO_API_TOKEN` is in your `.env`):

```bash
curl -X POST http://localhost:8001/mapeos \
  -H "Authorization: Bearer <MAPEO_API_TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{
    "moodle_user_id": 5,
    "moodle_username": "student1",
    "moodle_course_id": 2,
    "repo_url": "https://github.com/<org>/<student-repo>",
    "git_provider": "github"
  }'
```

---

### 6.5 Verify Everything Works

1. **Metrics dashboard** (`http://localhost:3001`): Log in with `profesor1` and their Moodle password. You should see the courses view.
2. **Chat (Element)** (`http://localhost:8081`): Log in as a student. The bot `@llm_wiki_bot:localhost` should appear in the student room automatically.
3. **Force sync** (optional): If the bot has not created the room, you can force synchronisation by restarting the workers:
   ```bash
   docker compose restart moodle-matrix-dev-sync-worker-1 moodle-matrix-dev-sync-worker-2
   ```
