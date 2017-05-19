##
# MIT License
#
# Copyright (c) 2016 Elias Saalmann, Christian Frommert, Simon Jakobi,
# Arne Jonas Präger, Maxi Bornmann, Georg Hackel, Eric Füg
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#

module Jekyll #:nodoc:
  module Drops #:nodoc:

    ##
    # Represents an RDF resource to the Liquid template engine
    #
    class RdfResource < RdfTerm

      ##
      # The Jekyll::Site of this Jekyll::Drops::RdfResource
      #
      attr_accessor :site

      ##
      # The Jekyll::RdfPageData of this Jekyll::Drops::RdfResource
      #
      attr_accessor :page

      ##
      # The relative path to the location on the disk where this resource is rendered to
      #
      attr_reader :render_path

      ##
      #
      #
      attr_accessor :subResources

      ##
      #
      #
      def initialize(term, sparql, site = nil, page = nil)
        super(term, sparql)
        if(site.is_a?(Jekyll::Site))
          @site = site
        end
        if(page.is_a?(Jekyll::Page))
          @page = page
        end
      end

      def addNecessities(site, page)
        if(site.is_a?(Jekyll::Site))
          @site ||= site
        end
        if(page.is_a?(Jekyll::Page))
          @page ||= page
        end
        return self
      end
      def ready?
        return (@site.is_a?(Jekyll::Site)||@page.is_a?(Jekyll::Page))
      end
      ##
      # Return a list of Jekyll::Drops::RdfStatements whose subject, predicate or object is the RDF resource represented by the receiver
      #
      def statements
        @statements ||= statements_as_subject + statements_as_predicate + statements_as_object
      end

      ##
      # Return a list of Jekyll::Drops::RdfStatements whose subject is the RDF resource represented by the receiver
      #
      def statements_as_subject
        @statements_as_subject ||= statements_as :subject
      end

      ##
      # Return a list of Jekyll::Drops::RdfStatements whose predicate is the RDF resource represented by the receiver
      #
      def statements_as_predicate
        @statements_as_predicate ||= statements_as :predicate
      end

      ##
      # Return a list of Jekyll::Drops::RdfStatements whose object is the RDF resource represented by the receiver
      #
      def statements_as_object
        @statements_as_object ||= statements_as :object
      end

      ##
      # Return a filename corresponding to the RDF resource represented by the receiver. The mapping between RDF resources and filenames should be bijective.
      #
      def filename(domain_name, baseurl)
        @filename ||= generate_file_name(domain_name, baseurl)
      end

      def directClasses
        @directClasses ||= begin
          classes=[]
          selection = statements_as(:subject).select{ |s| s.predicate.term.to_s=="http://www.w3.org/1999/02/22-rdf-syntax-ns#type" }
          unless selection.empty?
            selection.each{|s| classes << s.object.term.to_s}
          end
          classes.uniq!
          classes
        end
      end

      def iri
        term.to_s
      end

      ##
      # Return the URL of the page representing this RdfResource
      #
      def page_url
        page ? page.url.chomp('index.html') : term.to_s
      end

      ##
      # Return a list of RDF statements where the represented RDF resource plays a role
      # * +role+ - which role the represented RDF resource should play:
      #   :subject ::
      #     Return a list of Jekyll::Drops::RdfStatements whose subject is the RDF resource represented by the receiver
      #   :predicate ::
      #     Return a list of Jekyll::Drops::RdfStatements whose predicate is the RDF resource represented by the receiver
      #   :object ::
      #     Return a list of Jekyll::Drops::RdfStatements whose object is the RDF resource represented by the receiver
      #
      def statements_as(role)
        if(!term.to_s[0..1].eql? "_:")
          inputURI = "<#{term.to_s}>"
        elsif(:predicate.eql? role)
          return []
        else
          inputURI = term.to_s
        end

        case role
          when :subject
            query = "SELECT ?p ?o ?dt ?lit ?lang WHERE{ #{inputURI} ?p ?o BIND(datatype(?o) AS ?dt) BIND(isLiteral(?o) AS ?lit) BIND(lang(?o) AS ?lang)}"
            sparql.query(query).map do |solution|
              check = checkSolution(solution)
              createStatement(term.to_s, solution.p, solution.o, solution.lit, check[:lang], check[:dataType])
            end
          when :predicate
            query = "SELECT ?s ?o ?dt ?lit ?lang WHERE{ ?s #{inputURI} ?o BIND(datatype(?o) AS ?dt) BIND(isLiteral(?o) AS ?lit) BIND(lang(?o) AS ?lang)}"
            sparql.query(query).map do |solution|
              check = checkSolution(solution)
              createStatement(solution.s, term.to_s, solution.o, solution.lit, check[:lang], check[:dataType])
            end
          when :object
            query = "SELECT ?s ?p WHERE{ ?s ?p #{inputURI}}"
            sparql.query(query).map do |solution|
              createStatement( solution.s, solution.p, term.to_s)
            end
          else
            Jekyll.logger.error "Not existing role found in #{term.to_s}"
            return
        end
      end

      #checks if a query solution contains a language or type tag and returns those in a hash
      private
      def checkSolution(solution)
        result = {:lang => nil, :dataType => nil}
        if((solution.bound?(:lang)) && (!solution.lang.to_s.eql?("")))
          result[:lang] = solution.lang.to_s.to_sym
        end
        if(solution.bound? :dt)
          result[:dataType] = solution.dt
        end
        return result
      end

      private
      def createStatement(subjectString, predicateString, objectString, isLit = nil, lang = nil, dataType = nil)
        subject = RDF::URI(subjectString)
        predicate = RDF::URI(predicateString)
        if(!isLit.nil?&&isLit.true?)
          object = RDF::Literal(objectString, language: lang, datatype: RDF::URI(dataType))
        else
          object = RDF::URI(objectString)
        end
        return RdfStatement.new(RDF::Statement( subject, predicate, object), @sparql, @site)
      end

      private
      ##
      # Generate a filename corresponding to the RDF resource represented by the receiver. The mapping between RDF resources and filenames should be bijective. If the url of the rdf is the same as of the hosting site it will be omitted.
      # * +domain_name+
      #
      def generate_file_name(domain_name, baseurl)
        if(term.to_s[0..1].eql? "_:")
          file_name = "rdfsites/blanknode/#{term.to_s}/"
        else
          begin
            uri = URI::split(term.to_s)
            file_name = "rdfsites/" # in this directory all external RDF sites are stored
            if (uri[2] == domain_name)
              file_name = ""
              uri[0] = nil
              uri[2] = nil
              if(uri[5].length > baseurl.length)
                if(uri[5][0..(baseurl.length)].eql? (baseurl + "/"))
                  uri[5] = uri[5][(baseurl.length)..-1]
                end
              elsif(uri[5].eql?(baseurl))
                uri[5] = nil
              end
            end
            (0..8).each do |i|
              if !(uri[i].nil?)
                case i
                when 5
                  file_name += "#{uri[i][1..-1]}/"
                when 8
                  file_name += "#/#{uri[i]}"
                else
                  file_name += "#{uri[i]}/"
                end
              end
            end
            unless file_name[-1] == '/'
              file_name += '/'
            end
          rescue URI::InvalidURIError #unclean coding: blanknodes are recognized through errors
            file_name = "invalids/#{term.to_s}"
            Jekyll.logger.error("Invalid resource found: #{term.to_s} is not a proper uri")
          end
        end
        file_name = file_name.gsub('_','_u')
        file_name = file_name.gsub('//','/') # needs a better regex to include /// ////...
        file_name = file_name.gsub(':','_D')
        file_name = file_name.strip
        if(file_name[-2..-1] == "#/")
          file_name = file_name[0..-3]
        end
        file_name += 'index.html'
        @render_path = file_name
        file_name
      end

    end
  end
end
