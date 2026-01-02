# frozen_string_literal: true

require 'jekyll/page_without_a_file'
require 'set'

class BidirectionalLinksGenerator < Jekyll::Generator
  def generate(site)
    graph_nodes = []
    graph_edges = []
    tag_graph_nodes = []
    tag_graph_edges = []
    tag_note_ids = Set.new

    all_notes = site.collections['notes'].docs
    all_pages = site.pages

    all_docs = all_notes + all_pages

    link_extension = !!site.config["use_html_extension"] ? '.html' : ''

    # Convert all Wiki/Roam-style double-bracket link syntax to plain HTML
    # anchor tag elements (<a>) with "internal-link" CSS class
    all_docs.each do |current_note|
      all_docs.each do |note_potentially_linked_to|
        note_title_regexp_pattern = Regexp.escape(
          File.basename(
            note_potentially_linked_to.basename,
            File.extname(note_potentially_linked_to.basename)
          )
        ).gsub('\_', '[ _]').gsub('\-', '[ -]').capitalize

        title_from_data = note_potentially_linked_to.data['title']
        if title_from_data
          title_from_data = Regexp.escape(title_from_data)
        end

        new_href = "#{site.baseurl}#{note_potentially_linked_to.url}#{link_extension}"
        anchor_tag = "<a class='internal-link' href='#{new_href}'>\\1</a>"

        # Replace double-bracketed links with label using note title
        # [[A note about cats|this is a link to the note about cats]]
        current_note.content.gsub!(
          /\[\[#{note_title_regexp_pattern}\|(.+?)(?=\])\]\]/i,
          anchor_tag
        )

        # Replace double-bracketed links with label using note filename
        # [[cats|this is a link to the note about cats]]
        current_note.content.gsub!(
          /\[\[#{title_from_data}\|(.+?)(?=\])\]\]/i,
          anchor_tag
        )

        # Replace double-bracketed links using note title
        # [[a note about cats]]
        current_note.content.gsub!(
          /\[\[(#{title_from_data})\]\]/i,
          anchor_tag
        )

        # Replace double-bracketed links using note filename
        # [[cats]]
        current_note.content.gsub!(
          /\[\[(#{note_title_regexp_pattern})\]\]/i,
          anchor_tag
        )
      end

      # At this point, all remaining double-bracket-wrapped words are
      # pointing to non-existing pages, so let's turn them into disabled
      # links by greying them out and changing the cursor
      current_note.content = current_note.content.gsub(
        /\[\[([^\]]+)\]\]/i, # match on the remaining double-bracket links
        <<~HTML.delete("\n") # replace with this HTML (\\1 is what was inside the brackets)
          <span title='There is no note that matches this link.' class='invalid-link'>
            <span class='invalid-link-brackets'>[[</span>
            \\1
            <span class='invalid-link-brackets'>]]</span></span>
        HTML
      )
    end

    # Identify note backlinks and add them to each note
    all_notes.each do |current_note|
      # Nodes: Jekyll
      notes_linking_to_current_note = all_notes.filter do |e|
        e.url != current_note.url && e.content.include?(current_note.url)
      end

      # Nodes: Graph
      note_node = {
        id: note_id_from_note(current_note),
        path: "#{site.baseurl}#{current_note.url}#{link_extension}",
        label: current_note.data['title'],
        type: 'note',
      }

      graph_nodes << note_node unless current_note.path.include?('_notes/index.html')

      # Edges: Jekyll
      current_note.data['backlinks'] = notes_linking_to_current_note

      # Edges: Graph
      notes_linking_to_current_note.each do |n|
        graph_edges << {
          source: note_id_from_note(n),
          target: note_id_from_note(current_note),
        }
      end
    end

    site.tags.each do |tag_name, tagged_docs|
      tag_id = tag_id_from_name(tag_name)
      tag_slug = Jekyll::Utils.slugify(tag_name)

      tag_graph_nodes << {
        id: tag_id,
        path: "#{site.baseurl}/tags/#{tag_slug}#{link_extension}",
        label: tag_name,
        type: 'tag',
      }

      tagged_docs.each do |doc|
        next unless doc.respond_to?(:data)
        next unless doc.collection&.label == 'notes'

        note_id = note_id_from_note(doc)

        unless tag_note_ids.include?(note_id)
          tag_graph_nodes << {
            id: note_id,
            path: "#{site.baseurl}#{doc.url}#{link_extension}",
            label: doc.data['title'],
            type: 'note',
          }
          tag_note_ids.add(note_id)
        end

        tag_graph_edges << {
          source: note_id,
          target: tag_id,
        }
      end
    end

    File.write('_includes/notes_graph.json', JSON.dump({
      edges: graph_edges,
      nodes: graph_nodes,
    }))

    File.write('_includes/tags_graph.json', JSON.dump({
      edges: tag_graph_edges,
      nodes: tag_graph_nodes,
    }))
  end

  def note_id_from_note(note)
    note.data['title'].bytes.join
  end

  def tag_id_from_name(name)
    "tag-#{name.bytes.join}"
  end
end

class TagPagesGenerator < Jekyll::Generator
  priority :lowest
  safe true

  def generate(site)
    link_extension = site.config['use_html_extension'] ? '.html' : ''

    site.tags.each_key do |tag|
      tag_slug = Jekyll::Utils.slugify(tag)
      dir = File.join('tags', tag_slug)

      next if tag_page_exists?(site, tag, dir)

      site.pages << build_tag_page(site, dir, tag, link_extension)
    end
  end

  private

  def tag_page_exists?(site, tag, dir)
    site.pages.any? do |page|
      page.data['tag'] == tag ||
        page.url == "/#{dir}/" ||
        page.url == "/#{dir}" ||
        page.url == "/#{dir}.html"
    end
  end

  def build_tag_page(site, dir, tag, link_extension)
    Jekyll::PageWithoutAFile.new(site, site.source, dir, 'index.html').tap do |page|
      page.data['layout'] = 'tag'
      page.data['title'] = tag
      page.data['tag'] = tag
      page.data['type'] = 'tag'
      page.data['permalink'] = "/#{dir}#{link_extension}"
    end
  end
end
