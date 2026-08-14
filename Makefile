.PHONY: landing

landing:
	@echo "Posteight 랜딩페이지: http://localhost:4173"
	python3 -m http.server 4173 --directory Landing
