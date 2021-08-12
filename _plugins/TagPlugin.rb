module TagPlugin
    class TagGenerator < Jekyll::Generator
        safe true

        def generate(site)
            site.tags.each do |tag, filteredPosts|
                
                
                singleTagPage = TagPage.new(site, tag, filteredPosts)
                singleTagPage.render(site.layouts, site.site_payload)
                singleTagPage.write(site.dest)
                site.pages << singleTagPage
            end
        end
    end

    class TagPage < Jekyll::Page
        def initialize(site, tag, filteredPosts)
            defaultDir = "tag"
            
            @site = site
            @dir =  File.join(defaultDir, tag)
    
            @ext = '.html'
            @name = 'index.html'
           
            self.process(@name)
            self.read_yaml(File.join(site.source, '_layouts'), 'tag.html')
            self.data['title'] = tag
            self.data['filteredPosts'] = filteredPosts
            
            # self.data['tag'] = tag
            # self.data['title'] = '#' + tag
        end
    end
end