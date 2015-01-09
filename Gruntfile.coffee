module.exports = (grunt) ->

  grunt.initConfig
    test:
      options:
        bare: true
      expand: true
      src: ['test/**/*.coffee']
      dest: 'test'
      ext: '.js'

    mochacli:
      options:
        reporter: 'spec'
        colors: true
        compilers: ['coffee:coffee-script']
      all: ['./test/*.coffee']

    coffeelint:
      lib: ['*.coffee', 'src/*.coffee', 'test/*.coffee']
      options:
        'arrow_spacing': level: 'error'
        'colon_assignment_spacing': level: 'error', spacing: right: 1, left: 0
        'line_endings': level: 'error'
        'newlines_after_classes': level: 'error'
        'no_empty_param_list': level: 'error'
        'no_interpolation_in_single_quotes': level: 'error'
        'no_stand_alone_at': level: 'error'
        'no_unnecessary_double_quotes': level: 'error'
        'prefer_english_operator': level: 'error'
        'space_operators': level: 'error'
        'spacing_after_comma': level: 'error'

  grunt.loadNpmTasks 'grunt-contrib-coffee'
  grunt.loadNpmTasks 'grunt-mocha-cli'
  grunt.loadNpmTasks 'grunt-coffeelint'

  grunt.registerTask 'test', ['mochacli']
  grunt.registerTask 'lint', ['coffeelint']
