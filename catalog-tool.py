#!/usr/bin/env python3
import argparse
import json
import os
import re
import shutil
import sys
import tempfile
import urllib.error
import urllib.request
from pathlib import Path
from urllib.parse import urlparse


SCHEMA_VERSION = 1
KEY_PATTERN = re.compile(r"^[a-z0-9][a-z0-9-]*$")
PACKAGE_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9+._-]*$")
FLATPAK_ID_PATTERN = re.compile(r"^[A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+)+$")
GITHUB_PATTERN = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")
SHA256_PATTERN = re.compile(r"^[a-fA-F0-9]{64}$")
JSON_BLOCK_PATTERN = re.compile(r"```json\s*\n(.*?)\n```", re.DOTALL)
DISCOVERY_TYPES = {
    "none",
    "manual",
    "github",
    "direct",
    "page-deb",
    "redirect-deb",
    "redirect-rpm",
    "apt-index",
}
FLATPAK_SOURCE_TYPES = {"remote", "flatpakref"}


class CatalogError(ValueError):
    pass


def require_text(value, field, allow_empty=False):
    if not isinstance(value, str):
        raise CatalogError(f"{field} deve ser texto")
    if not allow_empty and not value.strip():
        raise CatalogError(f"{field} nao pode ser vazio")
    if any(character in value for character in ("|", "\t", "\r", "\n")):
        raise CatalogError(f"{field} contem separador, quebra de linha ou tabulacao")
    return value.strip()


def validate_https(value, field, allow_empty=True):
    value = require_text(value, field, allow_empty=allow_empty)
    if not value:
        return
    parsed = urlparse(value)
    if parsed.scheme != "https" or not parsed.netloc:
        raise CatalogError(f"{field} deve usar uma URL HTTPS")


def validate_package(value, field):
    value = require_text(value, field, allow_empty=True)
    if value and not PACKAGE_PATTERN.fullmatch(value):
        raise CatalogError(f"{field} possui nome de pacote invalido")


def validate_discovery(section, name):
    if not isinstance(section, dict):
        raise CatalogError(f"{name}.discovery deve ser um objeto")
    discovery_type = require_text(section.get("type", ""), f"{name}.discovery.type")
    source = require_text(section.get("source", ""), f"{name}.discovery.source", allow_empty=True)
    if discovery_type not in DISCOVERY_TYPES:
        raise CatalogError(f"{name}.discovery.type desconhecido: {discovery_type}")
    if discovery_type == "none" and source:
        raise CatalogError(f"{name}.discovery.source deve estar vazio para type=none")
    if discovery_type not in {"none", "manual"} and not source:
        raise CatalogError(f"{name}.discovery.source e obrigatorio")
    if discovery_type == "github":
        if not GITHUB_PATTERN.fullmatch(source):
            raise CatalogError(f"{name}.discovery.source nao e um repositorio GitHub valido")
    elif discovery_type not in {"none", "manual"}:
        first_url = source.split(";", 1)[0]
        validate_https(first_url, f"{name}.discovery.source", allow_empty=False)


def validate_resolved(section, name, extension):
    if not isinstance(section, dict):
        raise CatalogError(f"{name}.resolved deve ser um objeto")
    url = section.get("url", "")
    validate_https(url, f"{name}.resolved.url")
    if url and not urlparse(url).path.lower().endswith(extension):
        raise CatalogError(f"{name}.resolved.url deve apontar para {extension}")
    require_text(section.get("version", ""), f"{name}.resolved.version", allow_empty=True)
    sha256 = require_text(section.get("sha256", ""), f"{name}.resolved.sha256", allow_empty=True)
    if sha256 and not SHA256_PATTERN.fullmatch(sha256):
        raise CatalogError(f"{name}.resolved.sha256 deve conter 64 digitos hexadecimais")
    validate_https(section.get("checksum_url", ""), f"{name}.resolved.checksum_url")
    require_text(section.get("checked_at", ""), f"{name}.resolved.checked_at", allow_empty=True)
    status = require_text(section.get("status", ""), f"{name}.resolved.status")
    if status not in {"UNKNOWN", "FOUND", "NOT_FOUND", "ERROR"}:
        raise CatalogError(f"{name}.resolved.status invalido: {status}")


def validate_item(item, source="item"):
    if not isinstance(item, dict):
        raise CatalogError(f"{source}: item deve ser um objeto JSON")
    if item.get("schema_version") != SCHEMA_VERSION:
        raise CatalogError(f"{source}: schema_version deve ser {SCHEMA_VERSION}")
    order = item.get("order")
    if not isinstance(order, int) or order < 0:
        raise CatalogError(f"{source}: order deve ser um inteiro nao negativo")
    key = require_text(item.get("key", ""), "key")
    if not KEY_PATTERN.fullmatch(key):
        raise CatalogError(f"{source}: chave invalida: {key}")
    require_text(item.get("name", ""), "name")
    require_text(item.get("description", ""), "description")
    aliases = item.get("aliases")
    if not isinstance(aliases, list):
        raise CatalogError(f"{source}: aliases deve ser uma lista")
    for index, alias in enumerate(aliases):
        validate_package(alias, f"aliases[{index}]")

    packages = item.get("packages")
    if not isinstance(packages, dict):
        raise CatalogError(f"{source}: packages deve ser um objeto")
    for family in ("apt", "dnf", "zypper"):
        validate_package(packages.get(family, ""), f"packages.{family}")

    for name, extension in (("deb", ".deb"), ("rpm", ".rpm")):
        section = item.get(name)
        if not isinstance(section, dict):
            raise CatalogError(f"{source}: {name} deve ser um objeto")
        validate_discovery(section.get("discovery"), name)
        validate_resolved(section.get("resolved"), name, extension)

    flatpak = item.get("flatpak")
    if not isinstance(flatpak, dict):
        raise CatalogError(f"{source}: flatpak deve ser um objeto")
    flatpak_id = require_text(flatpak.get("id", ""), "flatpak.id")
    if not FLATPAK_ID_PATTERN.fullmatch(flatpak_id):
        raise CatalogError(f"{source}: ID Flatpak invalido: {flatpak_id}")
    source_type = require_text(flatpak.get("source_type", ""), "flatpak.source_type")
    if source_type not in FLATPAK_SOURCE_TYPES:
        raise CatalogError(f"{source}: flatpak.source_type invalido")
    require_text(flatpak.get("remote_name", ""), "flatpak.remote_name", allow_empty=True)
    validate_https(flatpak.get("repository_url", ""), "flatpak.repository_url")
    ref_or_url = require_text(flatpak.get("ref_or_url", ""), "flatpak.ref_or_url", allow_empty=True)
    if source_type == "remote" and not flatpak.get("repository_url"):
        raise CatalogError(f"{source}: flatpak.repository_url e obrigatorio para remote")
    if source_type == "flatpakref":
        validate_https(ref_or_url, "flatpak.ref_or_url", allow_empty=False)
    return item


def read_item(path):
    content = path.read_text(encoding="utf-8")
    matches = JSON_BLOCK_PATTERN.findall(content)
    if len(matches) != 1:
        raise CatalogError(f"{path}: esperado exatamente um bloco ```json```")
    try:
        item = json.loads(matches[0])
    except json.JSONDecodeError as error:
        raise CatalogError(f"{path}: JSON invalido: {error}") from error
    validate_item(item, str(path))
    if path.stem != item["key"]:
        raise CatalogError(f"{path}: nome do arquivo deve ser {item['key']}.md")
    return item


def load_library(directory):
    if not directory.is_dir():
        raise CatalogError(f"biblioteca nao encontrada: {directory}")
    items = []
    for path in sorted(directory.glob("*.md")):
        item = read_item(path)
        items.append(item)
    if not items:
        raise CatalogError("a biblioteca nao contem aplicativos")
    validate_collection(items)
    return sorted(items, key=lambda item: item["order"])


def validate_collection(items):
    for values, label in (
        ([item["key"] for item in items], "chave"),
        ([item["flatpak"]["id"] for item in items], "ID Flatpak"),
        ([item["order"] for item in items], "ordem"),
    ):
        if len(values) != len(set(values)):
            duplicate = next(value for value in values if values.count(value) > 1)
            raise CatalogError(f"{label} duplicado: {duplicate}")


def markdown_content(item):
    payload = json.dumps(item, ensure_ascii=True, indent=2, sort_keys=False)
    return f"# {item['name']}\n\n{item['description']}\n\n```json\n{payload}\n```\n"


def atomic_write(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists() and path.read_text(encoding="utf-8") == content:
        return
    if path.exists():
        backup = path.with_name(path.name + ".linux-setup.bak")
        if not backup.exists():
            shutil.copy2(path, backup)
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as temporary:
            temporary.write(content)
            temporary.flush()
            os.fsync(temporary.fileno())
        os.chmod(temporary_name, path.stat().st_mode & 0o777 if path.exists() else 0o644)
        os.replace(temporary_name, path)
    finally:
        if os.path.exists(temporary_name):
            os.unlink(temporary_name)


def write_item(directory, item):
    validate_item(item)
    path = directory / f"{item['key']}.md"
    if directory.is_dir() and any(directory.glob("*.md")):
        existing = load_library(directory)
        validate_collection([item] + [entry for entry in existing if entry["key"] != item["key"]])
    atomic_write(path, markdown_content(item))


def update_resolved(directory, key, format_name, status, checked_at, values):
    path = directory / f"{key}.md"
    if not path.exists():
        raise CatalogError(f"aplicativo nao encontrado: {key}")
    item = read_item(path)
    resolved = item[format_name]["resolved"]
    if status == "FOUND":
        resolved.update(values)
    resolved["status"] = status
    resolved["checked_at"] = checked_at
    write_item(directory, item)


def empty_resolved(url=""):
    return {
        "url": url,
        "version": "",
        "sha256": "",
        "checksum_url": "",
        "checked_at": "",
        "status": "UNKNOWN",
    }


def prompt_value(label, current="", required=False):
    suffix = f" [{current}]" if current else ""
    while True:
        value = input(f"{label}{suffix}: ").strip()
        if not value:
            value = current
        elif value == "-":
            value = ""
        if value or not required:
            return value
        print(f"{label} e obrigatorio.")


def edit_format(item, format_name):
    section = item[format_name]
    print(f"\nFonte {format_name.upper()}")
    discovery = section["discovery"]
    discovery["type"] = prompt_value("Tipo de descoberta", discovery["type"], required=True)
    discovery["source"] = "" if discovery["type"] == "none" else prompt_value(
        "Fonte de descoberta", discovery["source"], required=discovery["type"] != "manual",
    )
    resolved = section["resolved"]
    resolved["url"] = prompt_value("Link resolvido", resolved["url"])
    resolved["version"] = prompt_value("Versao", resolved["version"])
    resolved["sha256"] = prompt_value("SHA-256", resolved["sha256"])
    resolved["checksum_url"] = prompt_value("Link de checksum", resolved["checksum_url"])
    resolved["status"] = "UNKNOWN"
    resolved["checked_at"] = ""


def edit_item(item, creating=False):
    print("Digite - para limpar um campo opcional; Enter preserva o valor atual.")
    if creating:
        item["key"] = prompt_value("Chave", item["key"], required=True)
    item["name"] = prompt_value("Nome", item["name"], required=True)
    item["description"] = prompt_value("Descricao", item["description"], required=True)
    aliases = prompt_value("Aliases separados por ;", ";".join(item["aliases"]))
    item["aliases"] = [value.strip() for value in aliases.split(";") if value.strip()]
    for family in ("apt", "dnf", "zypper"):
        item["packages"][family] = prompt_value(f"Pacote {family.upper()}", item["packages"][family])
    edit_format(item, "deb")
    edit_format(item, "rpm")
    flatpak = item["flatpak"]
    print("\nFonte Flatpak")
    flatpak["id"] = prompt_value("ID Flatpak", flatpak["id"], required=True)
    flatpak["source_type"] = prompt_value("Tipo (remote ou flatpakref)", flatpak["source_type"], required=True)
    flatpak["remote_name"] = prompt_value("Nome do remoto", flatpak["remote_name"])
    flatpak["repository_url"] = prompt_value(
        "URL do repositorio", flatpak["repository_url"], required=flatpak["source_type"] == "remote",
    )
    flatpak["ref_or_url"] = prompt_value("Ref ou URL Flatpak", flatpak["ref_or_url"], required=True)
    validate_item(item)
    return item


def new_item(order):
    return {
        "schema_version": SCHEMA_VERSION, "order": order, "key": "", "name": "", "description": "",
        "aliases": [], "packages": {"apt": "", "dnf": "", "zypper": ""},
        "deb": {"discovery": {"type": "none", "source": ""}, "resolved": empty_resolved()},
        "rpm": {"discovery": {"type": "none", "source": ""}, "resolved": empty_resolved()},
        "flatpak": {"id": "", "source_type": "remote", "remote_name": "flathub",
                    "repository_url": "https://dl.flathub.org/repo/flathub.flatpakrepo", "ref_or_url": ""},
    }


def choose_item(items):
    for index, item in enumerate(items, 1):
        print(f"{index:2}. {item['name']} ({item['key']})")
    value = input("Numero ou chave: ").strip()
    if value.isdigit() and 1 <= int(value) <= len(items):
        return items[int(value) - 1]
    return next((item for item in items if item["key"] == value), None)


def check_url(url):
    request = urllib.request.Request(url, method="HEAD", headers={"User-Agent": "linux-setup"})
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            return 200 <= response.status < 400, str(response.status)
    except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError) as error:
        return False, str(getattr(error, "code", getattr(error, "reason", error)))


def validate_item_links(item):
    links = [(name.upper(), item[name]["resolved"]["url"]) for name in ("deb", "rpm")]
    flatpak = item["flatpak"]
    links.append(("FLATPAK", flatpak["repository_url"] if flatpak["source_type"] == "remote" else flatpak["ref_or_url"]))
    success = True
    for label, url in links:
        if not url:
            print(f"{label}: AUSENTE")
            continue
        valid, detail = check_url(url)
        print(f"{label}: {'OK' if valid else 'ERRO'} ({detail}) {url}")
        success = success and valid
    return success


def manage_library(directory, dry_run=False):
    while True:
        items = load_library(directory)
        print("\nGerenciar biblioteca\n1. Listar/detalhar\n2. Adicionar\n3. Editar\n4. Remover\n5. Validar links\n0. Voltar")
        option = input("> ").strip()
        if option == "0":
            return
        if option == "1":
            selected = choose_item(items)
            if selected:
                print(json.dumps(selected, ensure_ascii=True, indent=2))
        elif option == "2":
            candidate = edit_item(new_item(max(item["order"] for item in items) + 1), creating=True)
            if dry_run:
                print("[SIMULACAO] item validado; nenhuma escrita realizada")
            else:
                write_item(directory, candidate)
        elif option == "3":
            selected = choose_item(items)
            if selected:
                candidate = edit_item(json.loads(json.dumps(selected)))
                if dry_run:
                    print("[SIMULACAO] alteracao validada; nenhuma escrita realizada")
                else:
                    write_item(directory, candidate)
        elif option == "4":
            selected = choose_item(items)
            if selected and input(f"Digite {selected['key']} para confirmar: ").strip() == selected["key"]:
                if dry_run:
                    print("[SIMULACAO] item seria removido")
                else:
                    (directory / f"{selected['key']}.md").unlink()
                    load_library(directory)
        elif option == "5":
            selected = choose_item(items)
            if selected:
                validate_item_links(selected)


def discovery_for(resolver, source, format_name):
    if resolver == "none":
        return {"type": "none", "source": ""}, ""
    if resolver == "github":
        return {"type": "github", "source": source}, ""
    source_type, source_value = source.split(":", 1)
    supported = (
        format_name == "deb" and source_type in {"direct", "page-deb", "redirect-deb", "apt-index"}
    ) or (format_name == "rpm" and source_type in {"direct", "redirect-rpm"} and source_value.split("?", 1)[0].endswith(".rpm"))
    if not supported:
        return {"type": "none", "source": ""}, ""
    resolved_url = source_value if source_type == "direct" else ""
    return {"type": source_type, "source": source_value}, resolved_url


def parse_table(path):
    items = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.startswith("|") or line.startswith("|---") or line.startswith("| Chave"):
            continue
        values = [value.strip().strip("`") for value in line.strip().strip("|").split("|")]
        if len(values) != 10:
            raise CatalogError(f"linha invalida em {path}: {line}")
        key, flatpak_id, name, description, apt, dnf, zypper, resolver, source, aliases = values
        apt, dnf, zypper = ("" if value == "-" else value for value in (apt, dnf, zypper))
        source = "" if source == "-" else source
        deb_discovery, deb_url = discovery_for(resolver, source, "deb")
        rpm_discovery, rpm_url = discovery_for(resolver, source, "rpm")
        item = {
            "schema_version": SCHEMA_VERSION,
            "order": len(items),
            "key": key,
            "name": name,
            "description": description,
            "aliases": [value for value in aliases.split(";") if value and value != "-"],
            "packages": {"apt": apt, "dnf": dnf, "zypper": zypper},
            "deb": {"discovery": deb_discovery, "resolved": empty_resolved(deb_url)},
            "rpm": {"discovery": rpm_discovery, "resolved": empty_resolved(rpm_url)},
            "flatpak": {
                "id": flatpak_id,
                "source_type": "remote",
                "remote_name": "flathub",
                "repository_url": "https://dl.flathub.org/repo/flathub.flatpakrepo",
                "ref_or_url": flatpak_id,
            },
        }
        validate_item(item, key)
        items.append(item)
    return items


def export_tsv(items):
    for item in items:
        values = [
            item["key"], item["flatpak"]["id"], item["name"], item["description"],
            item["packages"]["apt"], item["packages"]["dnf"], item["packages"]["zypper"],
            item["deb"]["discovery"]["type"], item["deb"]["discovery"]["source"],
            item["rpm"]["discovery"]["type"], item["rpm"]["discovery"]["source"],
            ";".join(item["aliases"]), item["deb"]["resolved"]["url"],
            item["deb"]["resolved"]["version"], item["deb"]["resolved"]["sha256"],
            item["deb"]["resolved"]["checksum_url"], item["rpm"]["resolved"]["url"],
            item["rpm"]["resolved"]["version"], item["rpm"]["resolved"]["sha256"],
            item["rpm"]["resolved"]["checksum_url"], item["flatpak"]["source_type"],
            item["flatpak"]["remote_name"], item["flatpak"]["repository_url"],
            item["flatpak"]["ref_or_url"],
        ]
        print("|".join(str(value) for value in values))


def main():
    parser = argparse.ArgumentParser(description="Gerencia a biblioteca Markdown de aplicativos")
    subparsers = parser.add_subparsers(dest="command", required=True)
    for command in ("validate", "export-tsv"):
        subparser = subparsers.add_parser(command)
        subparser.add_argument("directory", type=Path)
    migrate = subparsers.add_parser("migrate-table")
    migrate.add_argument("table", type=Path)
    migrate.add_argument("directory", type=Path)
    show = subparsers.add_parser("show")
    show.add_argument("directory", type=Path)
    show.add_argument("key")
    upsert = subparsers.add_parser("upsert")
    upsert.add_argument("directory", type=Path)
    upsert.add_argument("json_file", type=Path)
    delete = subparsers.add_parser("delete")
    delete.add_argument("directory", type=Path)
    delete.add_argument("key")
    update = subparsers.add_parser("update-resolved")
    update.add_argument("directory", type=Path)
    update.add_argument("key")
    update.add_argument("format", choices=("deb", "rpm"))
    update.add_argument("status", choices=("FOUND", "NOT_FOUND", "ERROR"))
    update.add_argument("checked_at")
    update.add_argument("url", nargs="?", default="")
    update.add_argument("version", nargs="?", default="")
    update.add_argument("sha256", nargs="?", default="")
    update.add_argument("checksum_url", nargs="?", default="")
    manage = subparsers.add_parser("manage")
    manage.add_argument("directory", type=Path)
    manage.add_argument("--dry-run", action="store_true")
    arguments = parser.parse_args()

    if arguments.command == "migrate-table":
        arguments.directory.mkdir(parents=True, exist_ok=True)
        items = parse_table(arguments.table)
        for item in items:
            atomic_write(arguments.directory / f"{item['key']}.md", markdown_content(item))
        load_library(arguments.directory)
        print(f"OK: {len(items)} itens migrados")
        return

    if arguments.command == "update-resolved":
        values = {
            "url": arguments.url,
            "version": arguments.version,
            "sha256": arguments.sha256,
            "checksum_url": arguments.checksum_url,
        }
        update_resolved(
            arguments.directory, arguments.key, arguments.format,
            arguments.status, arguments.checked_at, values,
        )
        print(f"OK: {arguments.key} {arguments.format} {arguments.status}")
        return

    if arguments.command == "manage":
        manage_library(arguments.directory, dry_run=arguments.dry_run)
        return

    items = load_library(arguments.directory)
    if arguments.command == "validate":
        print(f"OK: {len(items)} itens validos")
    elif arguments.command == "export-tsv":
        export_tsv(items)
    elif arguments.command == "show":
        item = next((item for item in items if item["key"] == arguments.key), None)
        if item is None:
            raise CatalogError(f"aplicativo nao encontrado: {arguments.key}")
        print(json.dumps(item, ensure_ascii=True, indent=2))
    elif arguments.command == "upsert":
        item = json.loads(arguments.json_file.read_text(encoding="utf-8"))
        write_item(arguments.directory, item)
        print(f"OK: {item['key']} salvo")
    elif arguments.command == "delete":
        path = arguments.directory / f"{arguments.key}.md"
        if not path.exists():
            raise CatalogError(f"aplicativo nao encontrado: {arguments.key}")
        path.unlink()
        load_library(arguments.directory)
        print(f"OK: {arguments.key} removido")


if __name__ == "__main__":
    try:
        main()
    except (CatalogError, OSError, json.JSONDecodeError) as error:
        print(f"Erro: {error}", file=sys.stderr)
        raise SystemExit(1)