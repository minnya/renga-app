"""Sync store listing metadata (title/descriptions/images) to Google Play, without
touching any release track or binary.

r0adkll/upload-google-play (the GitHub Action used by deploy_to_play_store.yml) always
requires `releaseFiles` and has no metadata-only mode, so this talks to the Android
Publisher API directly via a single edit: insert -> listings.update -> images
deleteall+upload -> commit.

Usage:
  python sync_store_listing.py \
    --package-name com.minnya.renga \
    --service-account-json /path/to/service-account.json \
    --metadata-dir metadata/android \
    --locale en-US

Requires: google-api-python-client, google-auth (pip install, see
update_play_store_listing.yml).
"""

import argparse
import os

from google.oauth2 import service_account
from googleapiclient.discovery import build
from googleapiclient.http import MediaFileUpload

SCOPES = ["https://www.googleapis.com/auth/androidpublisher"]

# (imageType, path relative to <metadata-dir>/<locale>/images/) — single-file image types.
SINGLE_IMAGE_TYPES = [
    ("icon", "icon.png"),
    ("featureGraphic", "featureGraphic.png"),
]

# (imageType, directory relative to <metadata-dir>/<locale>/images/) — multi-file sets.
GALLERY_IMAGE_TYPES = [
    ("phoneScreenshots", "phoneScreenshots"),
    ("sevenInchScreenshots", "sevenInchScreenshots"),
    ("tenInchScreenshots", "tenInchScreenshots"),
]


def read_text(path):
    with open(path, encoding="utf-8") as f:
        return f.read().strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--package-name", required=True)
    parser.add_argument("--service-account-json", required=True)
    parser.add_argument("--metadata-dir", required=True, help="e.g. metadata/android")
    parser.add_argument("--locale", default="en-US")
    args = parser.parse_args()

    creds = service_account.Credentials.from_service_account_file(
        args.service_account_json, scopes=SCOPES
    )
    service = build("androidpublisher", "v3", credentials=creds)
    edits = service.edits()

    edit = edits.insert(body={}, packageName=args.package_name).execute()
    edit_id = edit["id"]
    print(f"Opened edit {edit_id}")

    locale_dir = os.path.join(args.metadata_dir, args.locale)
    images_dir = os.path.join(locale_dir, "images")

    edits.listings().update(
        packageName=args.package_name,
        editId=edit_id,
        language=args.locale,
        body={
            "language": args.locale,
            "title": read_text(os.path.join(locale_dir, "title.txt")),
            "shortDescription": read_text(
                os.path.join(locale_dir, "short_description.txt")
            ),
            "fullDescription": read_text(
                os.path.join(locale_dir, "full_description.txt")
            ),
        },
    ).execute()
    print("Updated listing text")

    def upload(image_type, file_path):
        media = MediaFileUpload(file_path, mimetype="image/png")
        edits.images().upload(
            packageName=args.package_name,
            editId=edit_id,
            language=args.locale,
            imageType=image_type,
            media_body=media,
        ).execute()

    for image_type, rel_path in SINGLE_IMAGE_TYPES:
        path = os.path.join(images_dir, rel_path)
        if not os.path.exists(path):
            continue
        edits.images().deleteall(
            packageName=args.package_name,
            editId=edit_id,
            language=args.locale,
            imageType=image_type,
        ).execute()
        upload(image_type, path)
        print(f"Uploaded {image_type}")

    for image_type, rel_dir in GALLERY_IMAGE_TYPES:
        dir_path = os.path.join(images_dir, rel_dir)
        if not os.path.isdir(dir_path):
            continue
        edits.images().deleteall(
            packageName=args.package_name,
            editId=edit_id,
            language=args.locale,
            imageType=image_type,
        ).execute()
        for fname in sorted(os.listdir(dir_path)):
            upload(image_type, os.path.join(dir_path, fname))
        print(f"Uploaded {image_type} ({len(os.listdir(dir_path))} images)")

    edits.commit(packageName=args.package_name, editId=edit_id).execute()
    print(f"Committed edit {edit_id}")


if __name__ == "__main__":
    main()
