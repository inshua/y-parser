import time
import timeit

import bs4
from y_parser import Parser, Scanner, Selector
from html.parser import HTMLParser
import lxml.html

def test2():
    # exhaust 0.8270473480224609
    s = open('y.html', 'r', encoding='utf-8').read()
    t = time.time()
    p = y_parser.Parser()
    p.feed(s)
    print('exhaust %s' % (time.time() - t))

    # exhaust 1.0420596599578857
    p2 = HTMLParser()
    p2.feed(s)
    print('exhaust %s' % (time.time() - t))

    # exhaust 1.1370651721954346
    p2 = lxml.html.HTMLParser()
    p2.feed(s)
    print('exhaust %s' % (time.time() - t))

def test3():
    def output(s):
        print(s)

    rules = [(['div#content.style-scope.ytd-app div#container div#meta > div#title-wrapper > h3 > a#video-title'], 'href')]
    s = open('y.html', 'r', encoding='utf-8').read()
    p = y_parser.Parser(rules, output)
    t = time.time()
    p.feed(s)
    print('exhaust %s' % (time.time() - t))

def test3():
    s = open('y.html', 'r', encoding='utf-8').read()
    # 'div#content.style-scope.ytd-app div#container div#meta > div#title-wrapper > h3 > a#video-title'
    def t():
        selector = Selector('div', id="content", classes=["style-scope","ytd-app"]).descendant(
            Selector('div', id="container").descendant(
                Selector('div', id='meta').child(
                    Selector('div', id="title-wrapper").child(Selector('h3').child(
                        Selector('a', id="video-title")
                    ))
                )
            )
        )
        scanner = Scanner(selector, 'href', debug=False)
        p = Parser(scanner)
        scanner.onfound = lambda s: 1
                # print('found %s' % s)
        p.feed(s)

    print(timeit.repeat(t, number=10))  # [8.675985372477756, 8.649958081539262, 8.725043121170973]

def test5():
    s = open('y.html', 'r', encoding='utf-8').read()
    def t():
        soup = bs4.BeautifulSoup(s, 'lxml')
        for link in soup.select('div#content div#container div#meta > div#title-wrapper > h3 > a#video-title'):
            #print(link.get('href'))
            pass

    print(timeit.repeat(t, number = 10))    #[2.5671789036285926, 2.5337672925677643, 2.512516845961363]


if __name__ == '__main__':
    test3()