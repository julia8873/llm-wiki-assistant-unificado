import os
import glob

def replace_in_files(directory, old_str, new_str):
    for root, dirs, files in os.walk(directory):
        for file in files:
            if file.endswith(".py") or file == "alembic.ini" or file == "pyproject.toml":
                filepath = os.path.join(root, file)
                with open(filepath, "r", encoding="utf-8") as f:
                    content = f.read()
                if old_str in content:
                    content = content.replace(old_str, new_str)
                    with open(filepath, "w", encoding="utf-8") as f:
                        f.write(content)

os.rename("src/metrics-api/app", "src/metrics-api/metrics_api")
replace_in_files("src/metrics-api", "from app", "from metrics_api")
replace_in_files("src/metrics-api", "import app", "import metrics_api")
replace_in_files("src/metrics-api", "app.core", "metrics_api.core")
replace_in_files("src/metrics-api", "packages = [\"app\"]", "packages = [\"metrics_api\"]")

# Fix hatchling in metrics-api if it doesn't exist yet
with open("src/metrics-api/pyproject.toml", "r", encoding="utf-8") as f:
    api_toml = f.read()
if "tool.hatch.build.targets.wheel" not in api_toml:
    with open("src/metrics-api/pyproject.toml", "a", encoding="utf-8") as f:
        f.write("\n[tool.hatch.build.targets.wheel]\npackages = [\"metrics_api\"]\n")

os.rename("src/metrics-worker/app", "src/metrics-worker/metrics_worker")
replace_in_files("src/metrics-worker", "from app", "from metrics_worker")
replace_in_files("src/metrics-worker", "import app", "import metrics_worker")
replace_in_files("src/metrics-worker", "packages = [\"app\"]", "packages = [\"metrics_worker\"]")
