from pathlib import Path

from alembic import command
from alembic.config import Config


def upgrade():
    root = Path(__file__).resolve().parent.parent
    config = Config()
    config.set_main_option("script_location", str(root / "migrations"))
    command.upgrade(config, "head")
    from .catalog_import import ensure_bundled
    from .config import settings

    if settings.environment != "test":
        ensure_bundled()


if __name__ == "__main__":
    upgrade()
