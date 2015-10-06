# Makefile to run samples accessing the web services
#
# Targets:
#   run_cpp     run all the cpp samples
#   run_ruby    run all the ruby samples
#   run_python  run all the python samples
#   all         all of the above
#
# Example
#  make run_python

${if ${strip ${IDILIA_ACCESS_KEY}},,${error IDILIA_ACCESS_KEY must be set}}
${if ${strip ${IDILIA_PRIVATE_KEY}},,${error IDILIA_PRIVATE_KEY must be set}}

#
# Targets to run all the samples

run_cpp:
	@g++ -o ./disambiguate_mpxml.cc.out -Wall -I /usr/include/libxml2 -lxml2 -lmhash -lcurl ./cpp/text/disambiguate_mpxml.cc
	./disambiguate_mpxml.cc.out
	@g++ -o ./match.json.cc.out -Wall -I /usr/include/libxml2 -lxml2 -lmhash -lcurl ./cpp/text/match_json.cc
	./match.json.cc.out
	@g++ -o ./paraphrase_xml.cc.out -Wall -I /usr/include/libxml2 -lxml2 -lmhash -lcurl ./cpp/text/paraphrase_xml.cc
	./paraphrase_xml.cc.out
	@g++ -o ./query.cc.out -Wall -I /usr/include/libxml2 -lxml2 -lmhash -lcurl ./cpp/kb/query.cc
	./query.cc.out
	@rm ./disambiguate_mpxml.cc.out ./match.json.cc.out ./query.cc.out ./paraphrase_xml.cc.out

queries.txt:
	echo "montreal canadians hockey" > $@
	echo "boston bruins playoff hopes" >> $@
	echo "mulroney iron ore president" >> $@
	
run_ruby: queries.txt
	ruby ./ruby/text/disambiguate_xml.rb
	ruby ./ruby/text/disambiguate_mpxml.rb
	ruby ./ruby/text/disambiguate_multiple_per_request.rb
	ruby ./ruby/text/disambiguate_multiple.rb --output-dir=/tmp --input-file=queries.txt
	ruby ./ruby/text/match_json.rb
	ruby ./ruby/text/paraphrase_xml.rb
	ruby ./ruby/text/paraphrase_json.rb
	ruby ./ruby/text/tag_json.rb
	ruby ./ruby/kb/query.rb
	ruby ./ruby/kb/tagging_menu.rb

run_python:
	python ./python/text/disambiguate_xml.py
	python ./python/text/disambiguate_mpxml.py
	python ./python/text/match_json.py
	python ./python/text/paraphrase_xml.py
	python ./python/text/paraphrase_json.py
	python ./python/kb/query.py

run_java:
	mvn -f java/pom.xml package
	mvn -f java/pom.xml exec:java -Dexec.mainClass=com.idilia.services.examples.text.Paraphrase
	mvn -f java/pom.xml exec:java -Dexec.mainClass=com.idilia.services.examples.text.Disambiguate
	mvn -f java/pom.xml exec:java -Dexec.mainClass=com.idilia.services.examples.kb.Query
	mvn -f java/pom.xml exec:java -Dexec.mainClass=com.idilia.services.examples.menu.TaggingMenu
	mvn -f java/pom.xml exec:java -Dexec.mainClass=com.idilia.services.examples.menu.TaggingMenuAsync

all: run_cpp run_ruby run_python run_java
