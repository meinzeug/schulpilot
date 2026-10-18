"""Artificial public navigation metadata; no captured private provider content."""

import copy


def sample_catalog():
    subjects = [
        {"id": key, "title": title, "url": "https://www.sofatutor.com/" + key}
        for key, title in (("mathematik", "Mathematik"), ("englisch", "Englisch"), ("biologie", "Biologie"))
    ]
    levels = [
        {
            "id": "grade-math-6",
            "subject_id": "mathematik",
            "title": "6. Klasse",
            "level_type": "klasse",
            "level_number": 6,
            "url": "https://www.sofatutor.com/mathematik/klasse-6",
        },
        {
            "id": "grade-english-1",
            "subject_id": "englisch",
            "title": "1. Lernjahr",
            "level_type": "lernjahr",
            "level_number": 1,
            "url": "https://www.sofatutor.com/englisch/lernjahr-1",
        },
        {
            "id": "grade-bio-6",
            "subject_id": "biologie",
            "title": "6. Klasse",
            "level_type": "klasse",
            "level_number": 6,
            "url": "https://www.sofatutor.com/biologie/klasse-6",
        },
    ]
    definitions = [
        ("add", "mathematik", "Brüche addieren", "grade-math-6"),
        ("expand", "mathematik", "Brüche erweitern", "grade-math-6"),
        ("empty", "mathematik", "Brüche kürzen", "grade-math-6"),
        ("past", "englisch", "Simple Past", "grade-english-1"),
        ("perfect", "englisch", "Present Perfect", "grade-english-1"),
        ("photo", "biologie", "Fotosynthese", "grade-bio-6"),
    ]
    topics, placements, contents, members = [], [], [], []
    for key, subject, title, level in definitions:
        topics.append(
            {
                "id": "topic-" + key,
                "subject_id": subject,
                "title": title,
                "entry_url": f"https://www.sofatutor.com/{subject}/videos/artificial-{key}?topic={key}",
                "curated_list_empty_verified": key == "empty",
            }
        )
        placements.append(
            {
                "topic_id": "topic-" + key,
                "grade_id": level,
                "area": "Künstliche Testthemen",
                "content_page_id": key,
                "entry_url": topics[-1]["entry_url"],
            }
        )
        if key == "empty":
            continue
        contents.append(
            {
                "id": "content-" + key,
                "title": title + " – künstliches Testvideo",
                "content_type": "video",
                "title_verified": True,
                "url": f"https://www.sofatutor.com/{subject}/videos/artificial-{key}",
            }
        )
        members.append(
            {
                "topic_id": "topic-" + key,
                "video_id": "content-" + key,
                "url": topics[-1]["entry_url"],
                "position": 1,
                "curated_class_membership_verified": True,
            }
        )
    # A genuine learning_text may have /videos/ in its retained URL.
    contents.extend(
        [
            {
                "id": "content-text",
                "title": "Brüche addieren – künstlicher Lerntext",
                "content_type": "learning_text",
                "title_verified": True,
                "url": "https://www.sofatutor.com/mathematik/videos/artificial-text",
            },
            {
                "id": "content-general",
                "title": "Kürzen – allgemeine Ergänzung",
                "content_type": "video",
                "title_verified": True,
                "url": "https://www.sofatutor.com/mathematik/videos/artificial-general",
            },
            {
                "id": "content-unverified",
                "title": "Ungeprüfter Einstieg",
                "content_type": "video",
                "title_verified": True,
                "url": "https://www.sofatutor.com/mathematik/videos/artificial-entry",
            },
        ]
    )
    members.extend(
        [
            {
                "topic_id": "topic-add",
                "video_id": "content-text",
                "url": contents[-3]["url"],
                "position": 2,
                "curated_class_membership_verified": True,
            },
            {
                "topic_id": "topic-empty",
                "video_id": "content-general",
                "url": contents[-2]["url"],
                "position": None,
                "curated_class_membership_verified": False,
            },
            {
                "topic_id": "topic-empty",
                "video_id": "content-unverified",
                "url": contents[-1]["url"],
                "position": None,
                "curated_class_membership_verified": False,
            },
        ]
    )
    return {
        "metadata": {
            "schema_version": "1.5",
            "provider": "sofatutor",
            "built_at": "2026-10-18T00:00:00Z",
            "contains_media": False,
        },
        "subjects": subjects,
        "grades": levels,
        "topics": topics,
        "topic_placements": placements,
        "videos": contents,
        "topic_videos": members,
        "sources": [],
        "public_topic_documents": [],
        "public_topic_links": [
            {
                "id": "public-1",
                "topic_id": "topic-empty",
                "video_id": "content-general",
                "url": contents[-2]["url"],
                "membership_verified": True,
                "membership_scope": "general_topic",
            }
        ],
        "content_metadata_sources": [],
        "sitemap_content_pages": [],
    }


def changed_catalog():
    data = copy.deepcopy(sample_catalog())
    data["metadata"]["built_at"] = "2026-10-19T00:00:00Z"
    data["videos"][0]["title"] += " aktualisiert"
    return data
