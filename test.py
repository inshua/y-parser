import time
import t6

def main() -> None:
    filename = './y.html'
    # filename = './style1.html'
    bys = open(filename, 'rb').read()
    arr = bytearray(bys)
    s = str(bys, encoding='utf-8')

    def t61():  # 0.071
        start = time.time()
        for i in range(10):
            t6.it(arr, len(arr))
        total = time.time() - start
        print("Total time: {:.3f}".format(total / 10))

    def t62():  # 0.0000
        start = time.time()
        for i in range(10000):
            t6.it_s(s)
        total = time.time() - start
        print("Total time: {:.4f}".format(total / 10000))

    #t61()
    t62()

if __name__ == '__main__':
    main()


