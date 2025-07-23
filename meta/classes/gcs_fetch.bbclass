python do_gcs_fetch() {
    import os
    import hashlib
    import shutil
    import tempfile
    import urllib.request
    import ssl
    import stat
    import time

    bucket = d.getVar("GCS_BUCKET")
    sha1_dir = d.getVar("GCS_SHA1_DIR")
    output_dir = d.getVar("GCS_OUTPUT_DIR")
    if not os.path.exists(sha1_dir):
        bb.warn(f"GCS_SHA1_DIR '{sha1_dir}' does not exist.")
        return
    if not os.path.exists(output_dir):
        os.makedirs(output_dir)
    for filename in os.listdir(sha1_dir):
        if not filename.endswith(".sha1"):
            continue
        filebase = os.path.splitext(filename)[0]
        sha1_file_path = os.path.join(sha1_dir, filename)
        output_file_path = os.path.join(output_dir, filebase)
        with open(sha1_file_path, "r", encoding="utf-8") as f:
            sha1 = f.read().strip()
        if os.path.exists(output_file_path):
            with open(output_file_path, "rb") as f:
                existing_sha1 = hashlib.sha1(f.read()).hexdigest()
                if existing_sha1 == sha1:
                    bb.note(f"{filebase} already exists and SHA1 matches. Skipping download.")
                    continue
        url = f"https://storage.googleapis.com/{bucket}/{sha1}"
        success = False
        for attempt in range(2):
            try:
                with urllib.request.urlopen(url, context=ssl.create_default_context()) as res:
                    with tempfile.NamedTemporaryFile(delete=False) as tmp_file:
                        shutil.copyfileobj(res, tmp_file)
                with open(tmp_file.name, "rb") as f:
                    downloaded_sha1 = hashlib.sha1(f.read()).hexdigest()
                    if downloaded_sha1 != sha1:
                        raise Exception("SHA1 mismatch after download")
                shutil.move(tmp_file.name, output_file_path)
                st = os.stat(output_file_path)
                os.chmod(output_file_path, st.st_mode | stat.S_IRWXU | stat.S_IRWXG | stat.S_IRWXO)
                bb.note(f"Downloaded and verified {filebase}")
                success = True
                break
            except Exception as e:
                bb.warn(f"Attempt {attempt+1} failed for {filebase}: {str(e)}")
                time.sleep(1)
        if not success:
            bb.error(f"Failed to download {filebase} after retries.")
}
