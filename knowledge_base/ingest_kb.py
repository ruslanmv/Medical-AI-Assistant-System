import os, pathlib
def main():
    kb_endpoint = os.getenv("KB_ENDPOINT", "http://localhost:8080")
    index_name = os.getenv("KB_INDEX_NAME", "medical-kb")
    sources_dir = pathlib.Path(__file__).parent / "sources"
    docs = [str(p) for p in sources_dir.glob("**/*") if p.is_file()]
    print(f"Ingest {len(docs)} documents into {kb_endpoint}/{index_name}")
    for d in docs[:10]:
        print(" -", d)
if __name__ == "__main__":
    main()
