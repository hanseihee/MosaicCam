#!/usr/bin/env python3
"""App Store Connect API로 출시 준비를 자동화한다.

필요한 것: App Store Connect API 키(App Manager 역할). 환경 변수로 준다.
  ASC_ISSUER_ID, ASC_KEY_ID, ASC_KEY_PATH(.p8 파일)

앱 레코드(앱 이름·번들 ID·SKU)는 API로 만들 수 없어 App Store Connect 웹에서 먼저 만들어야 한다.

사용:
  python3 Tools/asc_publish.py info                     # 앱·버전·빌드 상태
  python3 Tools/asc_publish.py metadata                 # 이름·부제·설명·키워드·카테고리·연령 등급 (40개 로케일)
  python3 Tools/asc_publish.py screenshots              # docs/appstore/screenshots 의 6.9인치 스크린샷 올리기
  python3 Tools/asc_publish.py iap                      # 광고 제거 상품 만들기(값·번역·심사 스크린샷)
  python3 Tools/asc_publish.py build                    # 아카이브 업로드 후 처리 완료되면 버전에 연결
  python3 Tools/asc_publish.py attach [빌드 번호]        # 이미 올린 빌드가 처리되면 버전에 연결(기본: project.yml 번호)
  python3 Tools/asc_publish.py submit                   # 심사 제출
"""
import hashlib
import json
import os
import pathlib
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import jwt  # PyJWT

ROOT = pathlib.Path(__file__).resolve().parent.parent
META = json.loads((ROOT / "docs/appstore/metadata.json").read_text())
COMMON, LOCALES = META["common"], META["locales"]
BUNDLE_ID = COMMON["bundleId"]
VERSION = "1.0.0"
API = "https://api.appstoreconnect.apple.com"
SHOTS = ROOT / "docs/appstore/screenshots"
# 로케일별 스크린샷 파일 접미사. 없는 로케일은 기본 언어(한국어) 것을 그대로 보여 준다
SHOT_LOCALES = {"ko": "ko", "en-US": "en", "en-GB": "en", "en-AU": "en", "en-CA": "en", "ja": "ja"}
DISPLAY_TYPE = "APP_IPHONE_67"  # 6.9인치 (1320×2868)


# MARK: - API 기본

def token():
    issuer, key_id, key_path = (os.environ.get(k) for k in ("ASC_ISSUER_ID", "ASC_KEY_ID", "ASC_KEY_PATH"))
    if not all((issuer, key_id, key_path)):
        sys.exit("ASC_ISSUER_ID, ASC_KEY_ID, ASC_KEY_PATH 환경 변수를 주세요")
    now = int(time.time())
    return jwt.encode({"iss": issuer, "iat": now, "exp": now + 1100, "aud": "appstoreconnect-v1"},
                      pathlib.Path(key_path).read_text(), algorithm="ES256", headers={"kid": key_id})


def call(method, path, body=None, params=None, raw=None, content_type="application/json"):
    url = path if path.startswith("http") else API + path
    if params:
        url += ("&" if "?" in url else "?") + urllib.parse.urlencode(params)
    data = raw if raw is not None else (json.dumps(body).encode() if body is not None else None)
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"Bearer {token()}")
    if data is not None:
        req.add_header("Content-Type", content_type)
    try:
        with urllib.request.urlopen(req) as res:
            text = res.read().decode()
            return json.loads(text) if text else {}
    except urllib.error.HTTPError as e:
        detail = e.read().decode()
        raise SystemExit(f"{method} {path} → {e.code}\n{detail[:2000]}")


def get_all(path, params=None):
    """목록을 끝까지 받는다"""
    out, url, p = [], path, dict(params or {})
    p.setdefault("limit", 200)
    while url:
        page = call("GET", url, params=p if url == path else None)
        out += page.get("data", [])
        url, p = page.get("links", {}).get("next"), None
    return out


def upload_asset(reserve_path, body, file_path):
    """예약 → 조각 업로드 → 체크섬 확정. 스크린샷·심사 스크린샷 공통"""
    data = file_path.read_bytes()
    body["data"]["attributes"].update({"fileName": file_path.name, "fileSize": len(data)})
    asset = call("POST", reserve_path, body)["data"]
    for op in asset["attributes"]["uploadOperations"]:
        chunk = data[op["offset"]:op["offset"] + op["length"]]
        req = urllib.request.Request(op["url"], data=chunk, method=op["method"])
        for h in op["requestHeaders"]:
            req.add_header(h["name"], h["value"])
        urllib.request.urlopen(req).read()
    call("PATCH", f"{reserve_path}/{asset['id']}", {"data": {
        "type": asset["type"], "id": asset["id"],
        "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}})
    return asset["id"]


# MARK: - 앱·버전 찾기

def app():
    found = call("GET", "/v1/apps", params={"filter[bundleId]": BUNDLE_ID})["data"]
    if not found:
        sys.exit(f"번들 ID {BUNDLE_ID}인 앱이 없어요. App Store Connect 웹에서 앱을 먼저 만들어 주세요.")
    return found[0]


EDITABLE_STATES = ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY")


def version(app_id):
    """편집할 수 있는 iOS 버전. 앱을 만들 때 생긴 '1.0'은 아카이브와 맞게 '1.0.0'으로 바꾼다"""
    versions = call("GET", f"/v1/apps/{app_id}/appStoreVersions", params={"filter[platform]": "IOS"})["data"]
    editable = [v for v in versions if v["attributes"]["appStoreState"] in EDITABLE_STATES]
    if editable:
        v = editable[0]
        if v["attributes"]["versionString"] != VERSION:
            print(f"버전 {v['attributes']['versionString']} → {VERSION}")
            v = call("PATCH", f"/v1/appStoreVersions/{v['id']}", {"data": {"type": "appStoreVersions", "id": v["id"],
                     "attributes": {"versionString": VERSION, "releaseType": "AFTER_APPROVAL"}}})["data"]
        return v
    # 심사 대기·잘못된 바이너리처럼 편집 불가 상태라도 같은 번호의 버전이 있으면 새로 만들지 않는다
    same = [v for v in versions if v["attributes"]["versionString"] == VERSION]
    if same:
        print(f"버전 {VERSION}은 {same[0]['attributes']['appStoreState']} 상태라 그대로 씁니다")
        return same[0]
    print(f"버전 {VERSION} 만드는 중")
    return call("POST", "/v1/appStoreVersions", {"data": {
        "type": "appStoreVersions",
        "attributes": {"platform": "IOS", "versionString": VERSION, "releaseType": "AFTER_APPROVAL"},
        "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})["data"]


def editable_app_info(app_id):
    infos = call("GET", f"/v1/apps/{app_id}/appInfos")["data"]
    editable = [i for i in infos if i["attributes"].get("state") in ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "WAITING_FOR_REVIEW")]
    return (editable or infos)[0]


def upsert_localizations(list_path, create_type, parent_type, parent_id, attrs_by_locale, create_rel_name):
    """있으면 PATCH, 없으면 POST"""
    existing = {l["attributes"]["locale"]: l for l in get_all(list_path)}
    for locale, attrs in attrs_by_locale.items():
        if locale in existing:
            call("PATCH", f"/v1/{create_type}/{existing[locale]['id']}",
                 {"data": {"type": create_type, "id": existing[locale]["id"], "attributes": attrs}})
        else:
            call("POST", f"/v1/{create_type}", {"data": {
                "type": create_type, "attributes": {**attrs, "locale": locale},
                "relationships": {create_rel_name: {"data": {"type": parent_type, "id": parent_id}}}}})
        print(f"  {locale} 완료")


# MARK: - 명령

def cmd_info():
    a = app()
    print("앱:", a["id"], a["attributes"]["name"], a["attributes"]["bundleId"])
    for v in call("GET", f"/v1/apps/{a['id']}/appStoreVersions")["data"]:
        print("버전:", v["attributes"]["versionString"], v["attributes"]["appStoreState"])
    for b in call("GET", "/v1/builds", params={"filter[app]": a["id"], "sort": "-uploadedDate", "limit": 5})["data"]:
        print("빌드:", b["attributes"]["version"], b["attributes"]["processingState"], b["attributes"]["uploadedDate"])
    for p in call("GET", f"/v1/apps/{a['id']}/inAppPurchasesV2")["data"]:
        print("인앱:", p["attributes"]["productId"], p["attributes"]["state"])
    for s in call("GET", f"/v1/apps/{a['id']}/reviewSubmissions", params={"include": "items"})["data"]:
        n = len(s.get("relationships", {}).get("items", {}).get("data") or [])
        print("심사 제출:", s["id"], s["attributes"]["state"], f"항목 {n}개", s["attributes"].get("submittedDate") or "")


def cmd_metadata():
    a = app()
    info = editable_app_info(a["id"])
    print("앱 정보(이름·부제·개인정보 주소)")
    upsert_localizations(f"/v1/appInfos/{info['id']}/appInfoLocalizations", "appInfoLocalizations", "appInfos", info["id"],
                         {loc: {"name": m["name"], "subtitle": m["subtitle"], "privacyPolicyUrl": COMMON["privacyPolicyUrl"]}
                          for loc, m in LOCALES.items()}, "appInfo")
    print("카테고리")
    call("PATCH", f"/v1/appInfos/{info['id']}", {"data": {"type": "appInfos", "id": info["id"], "relationships": {
        "primaryCategory": {"data": {"type": "appCategories", "id": COMMON["primaryCategory"]}},
        "secondaryCategory": {"data": {"type": "appCategories", "id": COMMON["secondaryCategory"]}}}}})
    print("연령 등급(해당 없음)")
    rating = call("GET", f"/v1/appInfos/{info['id']}/ageRatingDeclaration")["data"]
    none_keys = ["alcoholTobaccoOrDrugUseOrReferences", "contests", "gamblingSimulated", "gunsOrOtherWeapons",
                 "horrorOrFearThemes", "matureOrSuggestiveThemes", "medicalOrTreatmentInformation", "profanityOrCrudeHumor",
                 "sexualContentGraphicAndNudity", "sexualContentOrNudity", "violenceCartoonOrFantasy",
                 "violenceRealistic", "violenceRealisticProlongedGraphicOrSadistic"]
    false_keys = ["gambling", "unrestrictedWebAccess", "lootBox", "healthOrWellnessTopics", "messagingAndChat",
                  "parentalControls", "ageAssurance", "socialMedia", "socialMediaAgeRestricted", "userGeneratedContent"]
    call("PATCH", f"/v1/ageRatingDeclarations/{rating['id']}", {"data": {"type": "ageRatingDeclarations", "id": rating["id"], "attributes": {
        **{k: "NONE" for k in none_keys}, **{k: False for k in false_keys},
        "kidsAgeBand": None, "advertising": True}}})  # 광고 포함 표시
    print("콘텐츠 권한(제3자 콘텐츠 없음)")
    call("PATCH", f"/v1/apps/{a['id']}", {"data": {"type": "apps", "id": a["id"], "attributes": {"contentRightsDeclaration": "DOES_NOT_USE_THIRD_PARTY_CONTENT"}}})
    v = version(a["id"])
    # '새로운 기능'은 한 번이라도 출시된 뒤에만 쓸 수 있다
    released = any(x["attributes"]["appStoreState"] in ("READY_FOR_SALE", "READY_FOR_DISTRIBUTION", "PROCESSING_FOR_DISTRIBUTION")
                   for x in call("GET", f"/v1/apps/{a['id']}/appStoreVersions", params={"filter[platform]": "IOS"})["data"])
    print("버전 문구(설명·키워드·지원 주소" + ("·새로운 기능" if released else "") + ")")
    upsert_localizations(f"/v1/appStoreVersions/{v['id']}/appStoreVersionLocalizations", "appStoreVersionLocalizations", "appStoreVersions", v["id"],
                         {loc: {"description": m["description"], "keywords": m["keywords"], "supportUrl": COMMON["supportUrl"],
                                **({"whatsNew": m["whatsNew"]} if released else {})} for loc, m in LOCALES.items()}, "appStoreVersion")
    print("저작권")
    call("PATCH", f"/v1/appStoreVersions/{v['id']}", {"data": {"type": "appStoreVersions", "id": v["id"], "attributes": {"copyright": COMMON["copyright"]}}})
    print("심사 메모·연락처 (같은 계정의 다른 앱에 적힌 연락처를 그대로 쓴다)")
    detail = call("GET", f"/v1/appStoreVersions/{v['id']}/appStoreReviewDetail").get("data")
    attrs = {"notes": COMMON["reviewNotes"], "demoAccountRequired": False}
    for other in call("GET", "/v1/apps", params={"limit": 50})["data"]:
        if other["id"] == a["id"]:
            continue
        for ov in call("GET", f"/v1/apps/{other['id']}/appStoreVersions", params={"limit": 3})["data"]:
            od = call("GET", f"/v1/appStoreVersions/{ov['id']}/appStoreReviewDetail").get("data")
            if od and od["attributes"].get("contactEmail"):
                attrs.update({k: od["attributes"][k] for k in ("contactFirstName", "contactLastName", "contactPhone", "contactEmail")})
                break
        if "contactEmail" in attrs:
            break
    if detail:
        call("PATCH", f"/v1/appStoreReviewDetails/{detail['id']}", {"data": {"type": "appStoreReviewDetails", "id": detail["id"], "attributes": attrs}})
    else:
        call("POST", "/v1/appStoreReviewDetails", {"data": {"type": "appStoreReviewDetails", "attributes": attrs,
             "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": v["id"]}}}}})
    print("완료")


def cmd_pricing():
    """앱 값 무료, 판매 지역 확인"""
    a = app()
    if call("GET", f"/v1/apps/{a['id']}/appPriceSchedule").get("data"):
        print("앱 값: 이미 설정됨")
        points = []
    else:
        points = call("GET", f"/v1/apps/{a['id']}/appPricePoints", params={"filter[territory]": "KOR", "limit": 5})["data"]
    if points:
        free = next((p for p in points if float(p["attributes"]["customerPrice"]) == 0), None)
        if free is None:
            sys.exit("무료 가격 구간을 못 찾았어요")
        call("POST", "/v1/appPriceSchedules", {"data": {"type": "appPriceSchedules", "relationships": {
            "app": {"data": {"type": "apps", "id": a["id"]}},
            "baseTerritory": {"data": {"type": "territories", "id": "KOR"}},
            "manualPrices": {"data": [{"type": "appPrices", "id": "${p0}"}]}}},
            "included": [{"type": "appPrices", "id": "${p0}", "attributes": {"startDate": None},
                          "relationships": {"appPricePoint": {"data": {"type": "appPricePoints", "id": free["id"]}}}}]})
        print("앱 값: 무료")
    try:
        avail = call("GET", f"/v1/apps/{a['id']}/appAvailabilityV2", params={"include": "territoryAvailabilities", "limit[territoryAvailabilities]": 50})
    except SystemExit:
        avail = None
    if avail is None:
        territories = [t["id"] for t in get_all("/v1/territories")]
        call("POST", "/v2/appAvailabilities", {"data": {"type": "appAvailabilities", "attributes": {"availableInNewTerritories": True},
            "relationships": {"app": {"data": {"type": "apps", "id": a["id"]}},
                              "territoryAvailabilities": {"data": [{"type": "territoryAvailabilities", "id": f"${{t{i}}}"} for i in range(len(territories))]}}},
            "included": [{"type": "territoryAvailabilities", "id": f"${{t{i}}}", "attributes": {"available": True},
                          "relationships": {"territory": {"data": {"type": "territories", "id": t}}}} for i, t in enumerate(territories)]})
        print("판매 지역: 전체", len(territories), "곳 (새 지역 자동 포함)")
    else:
        n = sum(1 for t in avail.get("included", []) if t["attributes"].get("available"))
        print("판매 지역 설정돼 있음 (처음 50곳 중", n, "곳)")


def cmd_screenshots():
    a = app()
    v = version(a["id"])
    locs = {l["attributes"]["locale"]: l for l in get_all(f"/v1/appStoreVersions/{v['id']}/appStoreVersionLocalizations")}
    for locale, suffix in SHOT_LOCALES.items():
        if locale not in locs:
            print(f"{locale}: 버전 문구가 아직 없어요. metadata 먼저"); continue
        files = sorted(SHOTS.glob(f"[0-9]-*-{suffix}.png"))  # 1-home, 2-boxes, 3-masked 순서
        if not files:
            continue
        sets = call("GET", f"/v1/appStoreVersionLocalizations/{locs[locale]['id']}/appScreenshotSets")["data"]
        sset = next((s for s in sets if s["attributes"]["screenshotDisplayType"] == DISPLAY_TYPE), None)
        if sset is None:
            sset = call("POST", "/v1/appScreenshotSets", {"data": {"type": "appScreenshotSets",
                        "attributes": {"screenshotDisplayType": DISPLAY_TYPE},
                        "relationships": {"appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations", "id": locs[locale]["id"]}}}}})["data"]
        have = {s["attributes"]["fileName"] for s in get_all(f"/v1/appScreenshotSets/{sset['id']}/appScreenshots")}
        for f in files:
            if f.name in have:
                print(f"  {locale} {f.name} 이미 있음"); continue
            upload_asset("/v1/appScreenshots", {"data": {"type": "appScreenshots", "attributes": {},
                         "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": sset["id"]}}}}}, f)
            print(f"  {locale} {f.name} 올림")
    print("완료")


def cmd_iap():
    a = app()
    pid = COMMON["iapProductId"]
    existing = [p for p in call("GET", f"/v1/apps/{a['id']}/inAppPurchasesV2")["data"] if p["attributes"]["productId"] == pid]
    if existing:
        iap = existing[0]; print("상품 이미 있음:", iap["attributes"]["state"])
    else:
        iap = call("POST", "/v2/inAppPurchases", {"data": {"type": "inAppPurchases", "attributes": {
            "name": LOCALES["ko"]["iapName"], "productId": pid, "inAppPurchaseType": COMMON["iapType"],
            "reviewNote": "홈 화면 아래 '광고 없이 쓰기' → '₩3,000에 광고 제거'. 사면 저장할 때 광고가 나오지 않아요. / Home → 'Go ad-free' → 'Remove ads for ₩3,000'. Removes the interstitial shown on save."},
            "relationships": {"app": {"data": {"type": "apps", "id": a["id"]}}}}})["data"]
        print("상품 만듦")
    print("상품 번역")
    upsert_localizations(f"/v2/inAppPurchases/{iap['id']}/inAppPurchaseLocalizations", "inAppPurchaseLocalizations", "inAppPurchases", iap["id"],
                         {loc: {"name": m["iapName"], "description": m["iapDesc"]} for loc, m in LOCALES.items()}, "inAppPurchaseV2")
    print("값: 한국 ₩3,000 기준, 다른 나라는 Apple 환산")
    points = call("GET", f"/v2/inAppPurchases/{iap['id']}/pricePoints", params={"filter[territory]": "KOR", "limit": 200})["data"]
    point = next((p for p in points if float(p["attributes"]["customerPrice"]) == COMMON["iapPriceKRW"]), None)
    if point is None:
        sys.exit("₩3,000 가격 구간을 못 찾았어요: " + ", ".join(p["attributes"]["customerPrice"] for p in points[:30]))
    call("POST", "/v1/inAppPurchasePriceSchedules", {"data": {"type": "inAppPurchasePriceSchedules", "relationships": {
        "inAppPurchase": {"data": {"type": "inAppPurchases", "id": iap["id"]}},
        "baseTerritory": {"data": {"type": "territories", "id": "KOR"}},
        "manualPrices": {"data": [{"type": "inAppPurchasePrices", "id": "${price0}"}]}}},
        "included": [{"type": "inAppPurchasePrices", "id": "${price0}", "attributes": {"startDate": None},
                      "relationships": {"inAppPurchasePricePoint": {"data": {"type": "inAppPurchasePricePoints", "id": point["id"]}}}}]})
    print("판매 지역: 전체")
    territories = [t["id"] for t in get_all("/v1/territories")]
    call("POST", "/v1/inAppPurchaseAvailabilities", {"data": {"type": "inAppPurchaseAvailabilities",
        "attributes": {"availableInNewTerritories": True},
        "relationships": {"inAppPurchase": {"data": {"type": "inAppPurchases", "id": iap["id"]}},
                          "availableTerritories": {"data": [{"type": "territories", "id": t} for t in territories]}}}})
    shot = SHOTS / "iap-review-ko.png"
    if shot.exists() and not call("GET", f"/v2/inAppPurchases/{iap['id']}/appStoreReviewScreenshot").get("data"):
        upload_asset("/v1/inAppPurchaseAppStoreReviewScreenshots", {"data": {"type": "inAppPurchaseAppStoreReviewScreenshots", "attributes": {},
                     "relationships": {"inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": iap["id"]}}}}}, shot)
        print("심사 스크린샷 올림")
    print("완료. 버전 페이지의 '앱 내 구입' 항목에서 이 상품을 선택해 함께 제출해야 해요(웹에서만 됨).")


def cmd_build():
    a = app()
    v = version(a["id"])
    archive = ROOT / "build/MosaicCam.xcarchive"
    plist = ROOT / "build/ExportOptions-upload.plist"
    out = ROOT / "build/export-upload"
    subprocess.run(["rm", "-rf", str(out)])
    print("업로드 중 (몇 분 걸려요)")
    r = subprocess.run(["xcodebuild", "-exportArchive", "-archivePath", str(archive), "-exportOptionsPlist", str(plist),
                        "-exportPath", str(out), "-allowProvisioningUpdates",
                        "-authenticationKeyPath", os.environ["ASC_KEY_PATH"], "-authenticationKeyID", os.environ["ASC_KEY_ID"],
                        "-authenticationKeyIssuerID", os.environ["ASC_ISSUER_ID"]],
                       capture_output=True, text=True, env={**os.environ, "DEVELOPER_DIR": "/Applications/Xcode.app/Contents/Developer"})
    tail = "\n".join(l for l in (r.stdout + r.stderr).splitlines() if l.strip())[-1500:]
    if "EXPORT SUCCEEDED" not in r.stdout:
        sys.exit("업로드 실패:\n" + tail)
    print("업로드 끝. 처리 기다리는 중")
    cmd_attach()


def cmd_attach():
    """project.yml의 빌드 번호(또는 인자로 준 번호) 빌드가 처리되면 버전에 연결한다 (업로드는 하지 않음).
    최신 VALID 빌드를 고르면 새 빌드가 처리 중일 때 이전 빌드가 붙으므로 번호로 정확히 찾는다."""
    a = app()
    v = version(a["id"])
    number = sys.argv[2] if len(sys.argv) > 2 else build_number()
    for _ in range(60):
        builds = call("GET", "/v1/builds", params={"filter[app]": a["id"], "filter[version]": number, "limit": 1})["data"]
        state = builds[0]["attributes"]["processingState"] if builds else "업로드 목록에 아직 없음"
        if state == "VALID":
            call("PATCH", f"/v1/appStoreVersions/{v['id']}/relationships/build", {"data": {"type": "builds", "id": builds[0]["id"]}})
            print("버전에 빌드 연결:", number)
            return
        if state in ("FAILED", "INVALID"):
            sys.exit(f"빌드 {number} 처리 실패({state}). TestFlight 업로드 로그를 확인하세요.")
        print(f"빌드 {number}: {state}, 30초 뒤 다시 확인", flush=True)
        time.sleep(30)
    sys.exit("빌드 처리가 끝나지 않았어요. 잠시 뒤 다시 실행하세요.")


def build_number():
    for line in (ROOT / "project.yml").read_text(encoding="utf-8").splitlines():
        if "CURRENT_PROJECT_VERSION:" in line:
            return line.split(":", 1)[1].strip().strip('"')
    sys.exit("project.yml에서 CURRENT_PROJECT_VERSION을 찾지 못했어요.")


def cmd_submit():
    """초안(READY_FOR_REVIEW)이 있으면 재사용하고, 버전 항목이 없으면 넣은 뒤 제출한다.
    주의: 첫 인앱 상품은 API로 항목 추가가 안 된다(reviewSubmissionItems에 인앱 관계 없음).
    웹의 앱 내 구입 상세에서 '심사에 추가 → 해당 초안'을 먼저 눌러 둬야 한다."""
    a = app()
    v = version(a["id"])
    subs = call("GET", f"/v1/apps/{a['id']}/reviewSubmissions", params={"include": "items"})["data"]
    drafts = [s for s in subs if s["attributes"]["state"] == "READY_FOR_REVIEW" and s["attributes"]["platform"] == "IOS"]
    if drafts:
        sub = drafts[0]
        print("기존 초안 재사용:", sub["id"])
    else:
        sub = call("POST", "/v1/reviewSubmissions", {"data": {"type": "reviewSubmissions", "attributes": {"platform": "IOS"},
                   "relationships": {"app": {"data": {"type": "apps", "id": a["id"]}}}}})["data"]
    items = call("GET", f"/v1/reviewSubmissions/{sub['id']}/items", params={"include": "appStoreVersion"})
    has_version = any(i["type"] == "appStoreVersions" and i["id"] == v["id"] for i in items.get("included", []))
    if not has_version:
        call("POST", "/v1/reviewSubmissionItems", {"data": {"type": "reviewSubmissionItems",
             "relationships": {"reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sub["id"]}},
                               "appStoreVersion": {"data": {"type": "appStoreVersions", "id": v["id"]}}}}})
        print("버전 항목 추가")
    n = len(items["data"]) + (0 if has_version else 1)
    if n < 2:
        print("경고: 초안에 인앱 상품 항목이 없습니다. 웹에서 '심사에 추가'를 먼저 하세요. (항목 %d개)" % n)
    call("PATCH", f"/v1/reviewSubmissions/{sub['id']}", {"data": {"type": "reviewSubmissions", "id": sub["id"], "attributes": {"submitted": True}}})
    print("심사 제출 완료")


if __name__ == "__main__":
    cmds = {"info": cmd_info, "metadata": cmd_metadata, "pricing": cmd_pricing, "screenshots": cmd_screenshots, "iap": cmd_iap, "build": cmd_build, "attach": cmd_attach, "submit": cmd_submit}
    if len(sys.argv) < 2 or sys.argv[1] not in cmds:
        sys.exit(__doc__)
    cmds[sys.argv[1]]()
