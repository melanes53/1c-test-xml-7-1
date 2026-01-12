
import os
import re
import uuid
import sys

# --- Configuration ---
PROJECT_BASE_PATH = "1c-test-xml-7"
CONFIG_DIR = "Configuration"
DONOR_TYPE = "Catalog"
DONOR_NAME = "Предметы"
CLONE_NAME = "УТО_Тест"

# --- Helper Functions ---
def print_step(message): print(f"[*] {message}")
def print_success(message): print(f"[+] {message}")
def print_error(message): print(f"[!] {message}", file=sys.stderr)
def get_new_guid(): return str(uuid.uuid4())
def read_file(path): return open(path, "r", encoding="utf-8").read()
def write_file(path, content): open(path, "w", encoding="utf-8").write(content)

# --- Main Logic (Robust Text-Based) ---

def remove_existing_traces(base_path, clone_name):
    print_step(f"Ensuring idempotency by cleaning up traces of '{clone_name}'...")
    clone_ref_name = f"{DONOR_TYPE}.{clone_name}"

    for filename, pattern_template in [
        ("Configuration.xml", '.*<cfg:Catalog>{ref}</cfg:Catalog>.*\n?'),
        ("ConfigDumpInfo.xml", '<xr:Metadata>[\s\S]*?<xr:name>{ref}</xr:name>[\s\S]*?</xr:Metadata>\s*\n?')
    ]:
        path = os.path.join(base_path, filename)
        if not os.path.exists(path): continue
        content = read_file(path)
        pattern = re.compile(pattern_template.format(ref=re.escape(clone_ref_name)), re.MULTILINE)
        new_content = pattern.sub('', content)
        if content != new_content:
            write_file(path, new_content)
            print_success(f"Removed entry for '{clone_ref_name}' from {filename}")

    clone_file_path = os.path.join(base_path, "Catalogs", f"{clone_name}.xml")
    if os.path.exists(clone_file_path): os.remove(clone_file_path); print_success(f"Removed old file: {clone_file_path}")

def clone_and_regenerate(base_path, donor_name, clone_name):
    print_step(f"Cloning '{donor_name}' to '{clone_name}' via text manipulation...")
    donor_path = os.path.join(base_path, "Catalogs", f"{donor_name}.xml")
    clone_path = os.path.join(base_path, "Catalogs", f"{clone_name}.xml")
    if not os.path.exists(donor_path): raise FileNotFoundError(f"Donor file not found: {donor_path}")

    content = read_file(donor_path)
    content = content.replace(f".{donor_name}", f".{clone_name}").replace(f">{donor_name}<", f">{clone_name}<")
    print_success("Performed genetic string replacement.")

    uuid_pattern = re.compile(r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', re.IGNORECASE)
    content = uuid_pattern.sub(lambda m: get_new_guid(), content)
    print_success("Regenerated all UUIDs in the file.")

    write_file(clone_path, content)
    print_success(f"Saved new clone file to: {clone_path}")

def integrate_into_config(base_path, clone_name):
    print_step("Integrating clone into configuration topology via robust text insertion...")
    clone_ref_name = f"{DONOR_TYPE}.{clone_name}"

    # 1. Inject into Configuration.xml
    config_xml_path = os.path.join(base_path, "Configuration.xml")
    content = read_file(config_xml_path)
    new_line = f"\t\t\t<cfg:Catalog>{clone_ref_name}</cfg:Catalog>"
    
    # Find last catalog line
    catalog_lines = re.findall(r'(.*?<cfg:Catalog>.*</cfg:Catalog>)', content)
    if catalog_lines:
        last_line = catalog_lines[-1]
        content = content.replace(last_line, f'{last_line}\n{new_line}')
        print_success(f"Injected after last Catalog in {config_xml_path}")
    else:
        # If no catalogs, find first document
        doc_match = re.search(r'(\s*<cfg:Document>.*</cfg:Document>)', content)
        if doc_match:
            content = content.replace(doc_match.group(1), f'{new_line}\n{doc_match.group(1)}')
            print_success(f"Injected before first Document in {config_xml_path}")
        else:
            # If no documents, inject before ChildObjects closes
            content = content.replace('\t\t</cfg:ChildObjects>', f'{new_line}\n\t\t</cfg:ChildObjects>')
            print_success(f"Injected at end of ChildObjects in {config_xml_path}")
    write_file(config_xml_path, content)

    # 2. Inject into ConfigDumpInfo.xml
    config_dump_info_path = os.path.join(base_path, "ConfigDumpInfo.xml")
    content = read_file(config_dump_info_path)
    new_block = f'\t\t<xr:Metadata>\n\t\t\t<xr:name>{clone_ref_name}</xr:name>\n\t\t\t<xr:id>{get_new_guid()}</xr:id>\n\t\t</xr:Metadata>'

    meta_blocks = re.findall(r'(<xr:Metadata>[\s\S]*?<xr:name>Catalog\.[^<]+</xr:name>[\s\S]*?</xr:Metadata>)', content)
    if meta_blocks:
        last_block = meta_blocks[-1]
        content = content.replace(last_block, f'{last_block}\n{new_block}')
        print_success(f"Injected metadata after last Catalog in {config_dump_info_path}")
    else:
        doc_block_match = re.search(r'(<xr:Metadata>[\s\S]*?<xr:name>Document\.[^<]+</xr:name>[\s\S]*?</xr:Metadata>)', content)
        if doc_block_match:
            content = content.replace(doc_block_match.group(1), f'{new_block}\n{doc_block_match.group(1)}')
            print_success(f"Injected metadata before first Document in {config_dump_info_path}")
        else:
            content = content.replace('\t</xr:ChildObjects>', f'{new_block}\n\t</xr:ChildObjects>')
            print_success(f"Injected metadata at end of ChildObjects in {config_dump_info_path}")
    write_file(config_dump_info_path, content)

if __name__ == "__main__":
    try:
        config_path = os.path.join(PROJECT_BASE_PATH, CONFIG_DIR)
        if not os.path.isdir(config_path): config_path = PROJECT_BASE_PATH
        if not os.path.exists(os.path.join(config_path, 'Configuration.xml')): raise FileNotFoundError("Config files not found.")
        
        remove_existing_traces(config_path, CLONE_NAME)
        clone_and_regenerate(config_path, DONOR_NAME, CLONE_NAME)
        integrate_into_config(config_path, CLONE_NAME)
        print("\n\033[92mSUCCESS: Robust injection complete. Ready for /LoadConfigFromFiles.\033[0m")
    except Exception as e:
        print_error(f"A critical error occurred: {e}")
        import traceback; traceback.print_exc()
        sys.exit(1)
