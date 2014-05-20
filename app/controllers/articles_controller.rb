# -*- coding: utf-8 -*-
# Copyright © 2012 The Pennsylvania State University
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# -*- encoding : utf-8 -*-
require 'blacklight/catalog'
require 'blacklight_advanced_search'

# bl_advanced_search 1.2.4 is doing unitialized constant on these because we're calling ParseBasicQ directly
require 'parslet'  
require 'parsing_nesting/tree'
class ArticlesController < ApplicationController
  before_action :set_article, only: [:show, :edit, :update, :destroy]
  include Blacklight::Catalog
  # Extend Blacklight::Catalog with Hydra behaviors (primarily editing).
  include Hydra::Controller::ControllerBehavior
  include BlacklightAdvancedSearch::ParseBasicQ
  include Sufia::Controller
  #include Sufia::FilesControllerBehavior

  # These before_filters apply the hydra access controls
  #before_filter :enforce_show_permissions, :only=>:show
  before_filter :authenticate_user!, :except => [:show, :citation]
  before_filter :has_access?, :except => [:show]
  # This applies appropriate access controls to all solr queries
  ArticlesController.solr_search_params_logic += [:add_access_controls_to_solr_params]
  # This filters out objects that you want to exclude from search results, like FileAssets
  ArticlesController.solr_search_params_logic += [:exclude_unwanted_models]

  skip_before_filter :default_html_head


  # Catch permission errors
  rescue_from Hydra::AccessDenied, CanCan::AccessDenied do |exception|
    if exception.action == :edit
      #redirect_to action: 'show', alert: "You do not have sufficient privileges to edit this document"
      redirect_to action: 'show'
    elsif current_user and current_user.persisted?
      #redirect_to action: 'index', alert: exception.message
      redirect_to action: 'index'
    else
      session["user_return_to"] = request.url
      #redirect_to new_user_session_url, :alert => exception.message
      redirect_to new_user_session_url
    end
  end

  def index
    #@articles = Article.all
    #Grab the recent public documents
    #recent
    #@articles = @recent_documents
    #grab my recent docs
    recent_me
    @articles = @recent_user_documents
  end

  def show
    authorize! :show, params[:id]
    #puts @article.workflows
  end

  def new
    @article = Article.new
    @article.language.build()
    @article.subject.build()
  end

  def edit
    authorize! :edit, params[:id]
  end

  def create
    @article = Article.new
    @article.attributes = article_params
    #remove_blank_assertions for language
    lp = article_params['language']
    @article.language = nil
    #@article.language.build(lp)

    sp = article_params['subject']
    @article.subject = nil
 
    @article.apply_permissions(current_user) 

    # Save article
    respond_to do |format|
      if @article.save
        #TODO: This is a dirty way of adding language with the correct id. 
        #      Fix this double call of save. Generate ID when new?
        if !lp[:languageLabel].empty?
          lp.each do |k, v| 
            lp.delete(k) if v.empty?
          end
          lp['id'] = "info:fedora/#{@article.id}#language"
          @article.language.build(lp)
        end
        # Remove blank subjects
        sp.each do |s|
          if s[:subjectLabel].empty?
             sp.delete(s)
          end
        end
        #remove_blank_assertions for subject and build
        sp.each_with_index do |s, s_index|
          s.each do |k, v| 
            s.delete(k) if v.empty?
          end
          s['id'] = "info:fedora/#{@article.id}#subject#{s_index.to_s}"
          @article.subject.build(s)
        end
        @article.save
        #format.html { redirect_to article_path, notice: 'Article was successfully created.' }
        #format.html { redirect_to action: 'show', id: @article.id, notice: 'Article was successfully created.'}
        format.html { redirect_to action: 'show', id: @article.id }
        #format.html { render action: 'show', notice: 'Article was successfully created.', location: @article }
        format.json { render action: 'show', status: :created, location: @article }
      else
        format.html { render action: 'new' }
        format.json { render json: @article.errors, status: :unprocessable_entity }
      end
    end
  end

  def update
    lp = article_params['language']
    article_params.delete('language')

    sp = article_params['subject']
    article_params.delete('subject')

    # Update article
    respond_to do |format|
      if @article.update(article_params)
        # Save language and subject
        #TODO: Fix this dirty double call of update and save.
        #      Currently doing this to reset the length of subject to the new length.

        #remove_blank_assertions for language and build
        @article.language = nil
        if !lp[:languageLabel].empty?
          lp.each do |k, v| 
            lp.delete(k) if v.empty?
          end
          lp['id'] = "info:fedora/#{@article.id}#language"
          @article.language.build(lp)
        end
        #remove_blank_assertions for subject and build
        @article.subject = nil
        sp.each do |s|
          if s[:subjectLabel].empty?
             sp.delete(s)
          end
        end
        sp.each_with_index do |s, s_index|
          s.each do |k, v| 
            s.delete(k) if v.empty?
          end
          s['id'] = "info:fedora/#{@article.id}#subject#{s_index.to_s}"
          @article.subject.build(s)
        end
        @article.save

        format.html { redirect_to article_path, notice: 'Article was successfully updated.' }
        format.json { head :no_content }
      else
        format.html { render action: 'edit' }
        format.json { render json: @article.errors, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    #authorize! :edit, params[:id]
    @article.destroy
    respond_to do |format|
      format.html { redirect_to articles_url }
      format.json { head :no_content }
    end
  end

  def recent
    if user_signed_in?
      # grab other people's documents
      (_, @recent_documents) = get_search_results(:q =>filter_not_mine,
                                        :sort=>sort_field, :rows=>10)      
    else 
      # grab any documents we do not know who you are
      (_, @recent_documents) = get_search_results(:q =>'', :sort=>sort_field, :rows=>4)
    end
  end

  def recent_me
    if user_signed_in?
      (_, @recent_user_documents) = get_search_results(:q =>filter_mine,
                                        :sort=>sort_field, :rows=>10, :fields=>"*:*")
    end
  end

  def self.uploaded_field
#  system_create_dtsi
    solr_name('desc_metadata__date_uploaded', :stored_sortable, type: :date)
  end

  def self.modified_field
    solr_name('desc_metadata__date_modified', :stored_sortable, type: :date)
  end

  configure_blacklight do |config|
    ## Default parameters to send to solr for all search-like requests. See also SolrHelper#solr_search_params
    config.default_solr_params = {
      :qt => "search",
      :rows => 10
    }

    # solr field configuration for search results/index views
    config.index.show_link = solr_name("desc_metadata__title", :displayable)
    config.index.record_display_type = "id"

    # solr field configuration for document/show views
    config.show.html_title = solr_name("desc_metadata__title", :displayable)
    config.show.heading = solr_name("desc_metadata__title", :displayable)
    config.show.display_type = solr_name("has_model", :symbol)

    # solr fields that will be treated as facets by the blacklight application
    #   The ordering of the field names is the order of the display
    #config.add_facet_field solr_name("desc_metadata__resource_type", :facetable), :label => "Resource Type", :limit => 5
    config.add_facet_field solr_name("desc_metadata__type", :facetable), :label => "Resource Type", :limit => 5
    config.add_facet_field solr_name("MediatedSubmission_status", :symbol), :label => "Workflow Status", :limit => 5
    config.add_facet_field solr_name("desc_metadata__creator", :facetable), :label => "Creator", :limit => 5
    config.add_facet_field solr_name("desc_metadata__keyword", :facetable), :label => "Keyword", :limit => 5
    config.add_facet_field solr_name("desc_metadata__subject", :facetable), :label => "Subject", :limit => 5
    #config.add_facet_field solr_name("desc_metadata__based_near", :facetable), :label => "Location", :limit => 5
    config.add_facet_field solr_name("desc_metadata__publisher", :facetable), :label => "Publisher", :limit => 5


    #config.add_facet_field solr_name("file_format", :facetable), :label => "File Format", :limit => 5

    # Have BL send all facet field names to Solr, which has been the default
    # previously. Simply remove these lines if you'd rather use Solr request
    # handler defaults, or have no facets.
    config.add_facet_fields_to_solr_request!

    # solr fields to be displayed in the index (search results) view
    #   The ordering of the field names is the order of the display
    config.add_index_field solr_name("MediatedSubmission_status", :symbol), :label => "Workflow Status"
    config.add_index_field solr_name("desc_metadata__title", :stored_searchable, type: :string), :label => "Title"
    config.add_index_field solr_name("desc_metadata__subtitle", :stored_searchable, type: :string), :label => "Subtitle"
    config.add_index_field solr_name("desc_metadata__description", :stored_searchable, type: :string), :label => "Description"
    config.add_index_field solr_name("desc_metadata__abstract", :stored_searchable, type: :string), :label => "Abstract"
    config.add_index_field solr_name("desc_metadata__type", :stored_searchable, type: :string), :label => "Document type"
    config.add_index_field solr_name("desc_metadata__type_category", :stored_searchable, type: :string), :label => "Document category"
    config.add_index_field solr_name("desc_metadata__creator", :stored_searchable, type: :string), :label => "Creator"
    config.add_index_field solr_name("desc_metadata__contributor", :stored_searchable, type: :string), :label => "Contributor"
    config.add_index_field solr_name("desc_metadata__publisher", :stored_searchable, type: :string), :label => "Publisher"
    config.add_index_field solr_name("desc_metadata__keyword", :stored_searchable, type: :string), :label => "Keyword"
    config.add_index_field solr_name("desc_metadata__subject", :stored_searchable, type: :string), :label => "Subject"
    config.add_index_field solr_name("desc_metadata__medium", :stored_searchable, type: :string), :label => "Medium"
    config.add_index_field solr_name("desc_metadata__edition", :stored_searchable, type: :string), :label => "Edition"
    config.add_index_field solr_name("desc_metadata__numPages", :stored_searchable, type: :string), :label => "Number of pages"
    config.add_index_field solr_name("desc_metadata__pages", :stored_searchable, type: :string), :label => "Page range"
    config.add_index_field solr_name("desc_metadata__publicationStatus", :stored_searchable, type: :string), :label => "Publication status"
    config.add_index_field solr_name("desc_metadata__reviewStatus", :stored_searchable, type: :string), :label => "Review status"
    #config.add_index_field solr_name("desc_metadata__date_uploaded", :stored_searchable, type: :string), :label => "Date Uploaded"
    config.add_index_field solr_name("desc_metadata__date_modified", :stored_searchable, type: :string), :label => "Date Modified"
    config.add_index_field solr_name("desc_metadata__date_created", :stored_searchable, type: :string), :label => "Date Created"
    #config.add_index_field solr_name("desc_metadata__rights", :stored_searchable, type: :string), :label => "Rights"
    #config.add_index_field solr_name("desc_metadata__resource_type", :stored_searchable, type: :string), :label => "Resource Type"
    #config.add_index_field solr_name("desc_metadata__format", :stored_searchable, type: :string), :label => "File Format"
    config.add_index_field solr_name("desc_metadata__identifier", :stored_searchable, type: :string), :label => "Identifier"
    config.add_index_field solr_name("desc_metadata__language", :stored_searchable, type: :string), :label => "language"
    config.add_index_field solr_name("desc_metadata__languageCode", :stored_searchable, type: :string), :label => "Language code"
    config.add_index_field solr_name("desc_metadata__languageAuthority", :stored_searchable, type: :text), :label => "Language authority"
    config.add_index_field solr_name("desc_metadata__languageScheme", :stored_searchable, type: :text), :label => "Language scheme"

    # solr fields to be displayed in the show (single result) view
    #   The ordering of the field names is the order of the display
    config.add_show_field solr_name("desc_metadata__title", :stored_searchable, type: :string), :label => "Title"
    config.add_show_field solr_name("desc_metadata__subtitle", :stored_searchable, type: :string), :label => "Subtitle"
    config.add_show_field solr_name("desc_metadata__description", :stored_searchable, type: :string), :label => "Description"
    config.add_show_field solr_name("desc_metadata__abstract", :stored_searchable, type: :string), :label => "Abstract"
    config.add_show_field solr_name("desc_metadata__type", :stored_searchable, type: :string), :label => "Document type"
    config.add_show_field solr_name("desc_metadata__type_category", :stored_searchable, type: :string), :label => "Document category"
    config.add_show_field solr_name("desc_metadata__creator", :stored_searchable, type: :string), :label => "Creator"
    config.add_show_field solr_name("desc_metadata__contributor", :stored_searchable, type: :string), :label => "Contributor"
    config.add_show_field solr_name("desc_metadata__publisher", :stored_searchable, type: :string), :label => "Publisher"
    config.add_show_field solr_name("desc_metadata__keyword", :stored_searchable, type: :string), :label => "Keyword"
    config.add_show_field solr_name("desc_metadata__subject", :stored_searchable, type: :string), :label => "Subject"
    config.add_show_field solr_name("desc_metadata__medium", :stored_searchable, type: :string), :label => "Medium"
    config.add_show_field solr_name("desc_metadata__edition", :stored_searchable, type: :string), :label => "Edition"
    config.add_show_field solr_name("desc_metadata__numPages", :stored_searchable, type: :string), :label => "Number of pages"
    config.add_show_field solr_name("desc_metadata__pages", :stored_searchable, type: :string), :label => "Page range"
    config.add_show_field solr_name("desc_metadata__publicationStatus", :stored_searchable, type: :string), :label => "Publication status"
    config.add_show_field solr_name("desc_metadata__reviewStatus", :stored_searchable, type: :string), :label => "Review status"
    #config.add_show_field solr_name("desc_metadata__based_near", :stored_searchable, type: :string), :label => "Location"
    #config.add_show_field solr_name("desc_metadata__date_uploaded", :stored_searchable, type: :string), :label => "Date Uploaded"
    config.add_show_field solr_name("desc_metadata__date_modified", :stored_searchable, type: :string), :label => "Date Modified"
    config.add_show_field solr_name("desc_metadata__date_created", :stored_searchable, type: :string), :label => "Date Created"
    #config.add_show_field solr_name("desc_metadata__rights", :stored_searchable, type: :string), :label => "Rights"
    #config.add_show_field solr_name("desc_metadata__resource_type", :stored_searchable, type: :string), :label => "Resource Type"
    #config.add_show_field solr_name("desc_metadata__format", :stored_searchable, type: :string), :label => "File Format"
    config.add_show_field solr_name("desc_metadata__identifier", :stored_searchable, type: :string), :label => "Identifier"
    config.add_show_field solr_name("desc_metadata__language", :stored_searchable, type: :string), :label => "language"
    config.add_show_field solr_name("desc_metadata__languageCode", :stored_searchable, type: :string), :label => "Language code"
    config.add_show_field solr_name("desc_metadata__languageAuthority", :stored_searchable, type: :text), :label => "Language authority"
    config.add_show_field solr_name("desc_metadata__languageScheme", :stored_searchable, type: :text), :label => "Language scheme"

    # "fielded" search configuration. Used by pulldown among other places.
    # For supported keys in hash, see rdoc for Blacklight::SearchFields
    #
    # Search fields will inherit the :qt solr request handler from
    # config[:default_solr_parameters], OR can specify a different one
    # with a :qt key/value. Below examples inherit, except for subject
    # that specifies the same :qt as default for our own internal
    # testing purposes.
    #
    # The :key is what will be used to identify this BL search field internally,
    # as well as in URLs -- so changing it after deployment may break bookmarked
    # urls.  A display label will be automatically calculated from the :key,
    # or can be specified manually to be different.
    #
    # This one uses all the defaults set by the solr request handler. Which
    # solr request handler? The one set in config[:default_solr_parameters][:qt],
    # since we aren't specifying it otherwise.
    config.add_search_field('all_fields', :label => 'All Fields', :include_in_advanced_search => false) do |field|
      title_name = solr_name("desc_metadata__title", :stored_searchable, type: :string)
      label_name = solr_name("desc_metadata__title", :stored_searchable, type: :string)
      contributor_name = solr_name("desc_metadata__contributor", :stored_searchable, type: :string)
      field.solr_parameters = {
        :qf => "#{title_name} noid_tsi #{label_name} file_format_tesim #{contributor_name}",
        :pf => "#{title_name}"
      }
    end
    

    # Now we see how to over-ride Solr request handler defaults, in this
    # case for a BL "search field", which is really a dismax aggregate
    # of Solr search fields.
    # creator, title, description, publisher, date_created,
    # subject, language, resource_type, format, identifier, based_near,
    config.add_search_field('contributor') do |field|
      # solr_parameters hash are sent to Solr as ordinary url query params.
      field.solr_parameters = { :"spellcheck.dictionary" => "contributor" }

      # :solr_local_parameters will be sent using Solr LocalParams
      # syntax, as eg {! qf=$title_qf }. This is neccesary to use
      # Solr parameter de-referencing like $title_qf.
      # See: http://wiki.apache.org/solr/LocalParams
      solr_name = solr_name("desc_metadata__contributor", :stored_searchable, type: :string)
      field.solr_local_parameters = {
        :qf => solr_name,
        :pf => solr_name
      }
    end


    config.add_search_field('creator') do |field|
      field.solr_parameters = { :"spellcheck.dictionary" => "creator" }
      solr_name = solr_name("desc_metadata__creator", :stored_searchable, type: :string)
      field.solr_local_parameters = {
        :qf => solr_name,
        :pf => solr_name
      }
    end

    config.add_search_field('title') do |field|
      field.solr_parameters = {
        :"spellcheck.dictionary" => "title"
      }
      solr_name = solr_name("desc_metadata__title", :stored_searchable, type: :string)
      field.solr_local_parameters = {
        :qf => solr_name,
        :pf => solr_name
      }
    end

    config.add_search_field('subtitle') do |field|
      field.solr_parameters = {
        :"spellcheck.dictionary" => "subtitle"
      }
      solr_name = solr_name("desc_metadata__subtitle", :stored_searchable, type: :string)
      field.solr_local_parameters = {
        :qf => solr_name,
        :pf => solr_name
      }
    end

    config.add_search_field('description') do |field|
      field.label = "Abstract or Summary"
      field.solr_parameters = {
        :"spellcheck.dictionary" => "description"
      }
      solr_name = solr_name("desc_metadata__description", :stored_searchable, type: :string)
      field.solr_local_parameters = {
        :qf => solr_name,
        :pf => solr_name
      }
    end

    config.add_search_field('abstract') do |field|
      field.label = "Abstract or Summary"
      field.solr_parameters = {
        :"spellcheck.dictionary" => "abstract"
      }
      solr_name = solr_name("desc_metadata__abstract", :stored_searchable, type: :string)
      field.solr_local_parameters = {
        :qf => solr_name,
        :pf => solr_name
      }
    end

    config.add_search_field('type') do |field|
      field.label = "Document type"
      field.solr_parameters = {
        :"spellcheck.dictionary" => "type"
      }
      solr_name = solr_name("desc_metadata__type", :stored_searchable, type: :string)
      field.solr_local_parameters = {
        :qf => solr_name,
        :pf => solr_name
      }
    end

    config.add_search_field('type_category') do |field|
      field.label = "Document category"
      field.solr_parameters = {
        :"spellcheck.dictionary" => "type_category"
      }
      solr_name = solr_name("desc_metadata__type_category", :stored_searchable, type: :string)
      field.solr_local_parameters = {
        :qf => solr_name,
        :pf => solr_name
      }
    end

    config.add_search_field('publisher') do |field|
      field.solr_parameters = {
        :"spellcheck.dictionary" => "publisher"
      }
      solr_name = solr_name("desc_metadata__publisher", :stored_searchable, type: :string)
      field.solr_local_parameters = {
        :qf => solr_name,
        :pf => solr_name
      }
    end

    config.add_search_field('subject') do |field|
      field.solr_parameters = {
        :"spellcheck.dictionary" => "subject"
      }
      solr_name = solr_name("desc_metadata__subject", :stored_searchable, type: :string)
      field.solr_local_parameters = {
        :qf => solr_name,
        :pf => solr_name
      }
    end

    config.add_search_field('medium') do |field|
      field.solr_parameters = {
        :"spellcheck.dictionary" => "medium"
      }
      solr_name = solr_name("desc_metadata__medium", :stored_searchable, type: :string)
      field.solr_local_parameters = {
        :qf => solr_name,
        :pf => solr_name
      }
    end

    config.add_search_field('edition') do |field|
      field.solr_parameters = {
        :"spellcheck.dictionary" => "edition"
      }
      solr_name = solr_name("desc_metadata__edition", :stored_searchable, type: :string)
      field.solr_local_parameters = {
        :qf => solr_name,
        :pf => solr_name
      }
    end

    config.add_search_field('numPages') do |field|
      field.label = "Number of pages"
      field.solr_parameters = {
        :"spellcheck.dictionary" => "numPages"
      }
      solr_name = solr_name("desc_metadata__numPages", :stored_searchable, type: :string)
      field.solr_local_parameters = {
        :qf => solr_name,
        :pf => solr_name
      }
    end

    config.add_search_field('pages') do |field|
      field.label = "Page range"
      field.solr_parameters = {
        :"spellcheck.dictionary" => "pages"
      }
      solr_name = solr_name("desc_metadata__numPages", :stored_searchable, type: :string)
      field.solr_local_parameters = {
        :qf => solr_name,
        :pf => solr_name
      }
    end

    config.add_search_field('publicationStatus') do |field|
      field.label = "Publication status"
      field.solr_parameters = {
        :"spellcheck.dictionary" => "publicationStatus"
      }
      solr_name = solr_name("desc_metadata__publicationStatus", :stored_searchable, type: :string)
      field.solr_local_parameters = {
        :qf => solr_name,
        :pf => solr_name
      }
    end

    config.add_search_field('reviewStatus') do |field|
      field.label = "Review status"
      field.solr_parameters = {
        :"spellcheck.dictionary" => "reviewStatus"
      }
      solr_name = solr_name("desc_metadata__reviewStatus", :stored_searchable, type: :string)
      field.solr_local_parameters = {
        :qf => solr_name,
        :pf => solr_name
      }
    end

    #config.add_search_field('format') do |field|
    #  field.include_in_advanced_search = false
    #  field.solr_parameters = {
    #    :"spellcheck.dictionary" => "format"
    #  }
    #  solr_name = solr_name("desc_metadata__format", :stored_searchable, type: :string)
    #  field.solr_local_parameters = {
    #    :qf => solr_name,
    #    :pf => solr_name
    #  }
    #end

    config.add_search_field('identifier') do |field|
      field.include_in_advanced_search = false
      field.solr_parameters = {
        :"spellcheck.dictionary" => "identifier"
      }
      solr_name = solr_name("desc_metadata__id", :stored_searchable, type: :string)
      field.solr_local_parameters = {
        :qf => solr_name,
        :pf => solr_name
      }
    end

    #config.add_search_field('based_near') do |field|
    #  field.label = "Location"
    #  field.solr_parameters = {
    #    :"spellcheck.dictionary" => "based_near"
    #  }
    #  solr_name = solr_name("desc_metadata__based_near", :stored_searchable, type: :string)
    #  field.solr_local_parameters = {
    #    :qf => solr_name,
    #    :pf => solr_name
    #  }
    #end

    config.add_search_field('keyword') do |field|
      field.solr_parameters = {
        :"spellcheck.dictionary" => "keyword"
      }
      solr_name = solr_name("desc_metadata__keyword", :stored_searchable, type: :string)
      field.solr_local_parameters = {
        :qf => solr_name,
        :pf => solr_name
      }
    end

    #config.add_search_field('depositor') do |field|
    #  solr_name = solr_name("desc_metadata__depositor", :stored_searchable, type: :string)
    #  field.solr_local_parameters = {
    #    :qf => solr_name,
    #    :pf => solr_name
    #  }
    #end

    #config.add_search_field('rights') do |field|
    #  solr_name = solr_name("desc_metadata__rights", :stored_searchable, type: :string)
    #  field.solr_local_parameters = {
    #    :qf => solr_name,
    #    :pf => solr_name
    #  }
    #end

    config.add_search_field('date_modified') do |field|
      field.solr_parameters = {
        :"spellcheck.dictionary" => "date_modified"
      }
      solr_name = solr_name("desc_metadata__modified", :stored_searchable, type: :string)
      field.solr_local_parameters = {
        :qf => solr_name,
        :pf => solr_name
      }
    end

    config.add_search_field('date_created') do |field|
      field.solr_parameters = {
        :"spellcheck.dictionary" => "date_created"
      }
      solr_name = solr_name("desc_metadata__created", :stored_searchable, type: :string)
      field.solr_local_parameters = {
        :qf => solr_name,
        :pf => solr_name
      }
    end

    config.add_search_field('language') do |field|
      field.label = "Language"
      field.solr_parameters = {
        :"spellcheck.dictionary" => "language"
      }
      solr_name = solr_name("desc_metadata__language", :stored_searchable, type: :string)
      field.solr_local_parameters = {
        :qf => solr_name,
        :pf => solr_name
      }
    end

    config.add_search_field('languageCode') do |field|
      field.label = "Language code"
      field.solr_parameters = {
        :"spellcheck.dictionary" => "languageCode"
      }
      solr_name = solr_name("desc_metadata__languageCode", :stored_searchable, type: :string)
      field.solr_local_parameters = {
        :qf => solr_name,
        :pf => solr_name
      }
    end

    config.add_search_field('languageAuthority') do |field|
      field.label = "Language authority"
      field.solr_parameters = {
        :"spellcheck.dictionary" => "languageAuthority"
      }
      solr_name = solr_name("desc_metadata__languageAuthority", :stored_searchable, type: :text)
      field.solr_local_parameters = {
        :qf => solr_name,
        :pf => solr_name
      }
    end

    config.add_search_field('languageScheme') do |field|
      field.label = "Language scheme"
      field.solr_parameters = {
        :"spellcheck.dictionary" => "languageScheme"
      }
      solr_name = solr_name("desc_metadata__languageScheme", :stored_searchable, type: :text)
      field.solr_local_parameters = {
        :qf => solr_name,
        :pf => solr_name
      }
    end

    # "sort results by" select (pulldown)
    # label in pulldown is followed by the name of the SOLR field to sort by and
    # whether the sort is ascending or descending (it must be asc or desc
    # except in the relevancy case).
    # label is key, solr field is value
    config.add_sort_field "score desc, #{uploaded_field} desc", :label => "relevance \u25BC"
    config.add_sort_field "#{uploaded_field} desc", :label => "date uploaded \u25BC"
    config.add_sort_field "#{uploaded_field} asc", :label => "date uploaded \u25B2"
    config.add_sort_field "#{modified_field} desc", :label => "date modified \u25BC"
    config.add_sort_field "#{modified_field} asc", :label => "date modified \u25B2"

    # If there are more than this many search results, no spelling ("did you
    # mean") suggestion is offered.
    config.spell_max = 5
  end

  private
    def article_params
    #  #params.require(:article).permit(:title, :subtitle, :description, :abstract, {:keyword => []}, :medium, :numPages, :pages, :publicationStatus, :reviewStatus, :language, :language_attributes, :workflows, :workflows_attributes, :permissions, :permissions_attributes, :subject, :scheme, :elementList, :externalAuthority, :topicElement_attributes, :topicElement, :scheme_attributes)
    #  params.require(:article).permit!
    params.require(:article)
    end

  def set_article
    @article = Article.find(params[:id])
  end

  protected

  # Limits search results just to GenericFiles
  # @param solr_parameters the current solr parameters
  # @param user_parameters the current user-subitted parameters

  def exclude_unwanted_models(solr_parameters, user_parameters)
    solr_parameters[:fq] ||= []
    solr_parameters[:fq] << "#{Solrizer.solr_name("has_model", :symbol)}:\"info:fedora/afmodel:Article\""
  end

  def depositor
  #  #Hydra.config[:permissions][:owner] maybe it should match this config variable, but it doesn't.
    Solrizer.solr_name('depositor', :stored_searchable, type: :string)
  end

  def filter_not_mine 
    "{!lucene q.op=AND df=#{depositor}}-#{current_user.user_key}"
  end

  def filter_mine
    "{!lucene q.op=AND df=#{depositor}}#{current_user.user_key}"
  end

  def sort_field
    "#{Solrizer.solr_name('system_create', :sortable)} desc"
  end

  def has_access?
    true
  end

end
