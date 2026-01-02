---
title: Notes
layout: page
permalink: /notes
---

<h1>📚 Notes</h1>
<p>所有笔记自动按标题排序，点击即可跳转。</p>

{% assign notes_collection = site.collections.notes %}
{% if notes_collection %}
  {% assign all_notes = notes_collection.docs | sort: 'title' %}
  <ul>
    {% for note in all_notes %}
      <li><a class="internal-link" href="{{ note.url | relative_url }}">{{ note.title }}</a></li>
    {% endfor %}
  </ul>
{% else %}
  <p class="tag-empty">暂未找到 notes 集合。</p>
{% endif %}

