import io

cdef enum MessageType:
    mt_text = 1
    mt_gt = 2
    mt_slash = 3
    mt_lt = 4
    mt_double_quote = 5
    mt_single_quote = 6
    mt_space = 7
    mt_eq = 8
    mt_value_end = 9
    mt_comment_end = 10
    mt_star = 11    # × script, style 内有效


cdef enum Action:
    act_undetermine = 1  # 不确定
    act_resume = 2  # 不确定的内容归属上一个内容
    act_throw = 4  # 不确定的内容抛弃
    act_start = 8  # 新内容，可组合，默认抛弃前面的不确定内容
    act_end = 16  # 结束，可组合，默认抛弃前面的不确定内容
    act_pass = 32  # 跳过本字符
    act_append = 64  # 接受本字符并继续，单独用
    act_reject = 256    # 回退上一状态（undetermine之前的状态)
    act_error = 128  # 发生错误

cdef struct ParseResult:
    int state
    int sub
    int sub2
    int changed
    int action
    int maybe_regexp
    
cdef enum ParseState:
    ps_none = 0
    ps_text = 1
    ps_will_tag = 2     #<
    ps_will_dtd = 3     #<!
    ps_will_comment = 4  # <!-
    ps_dtd = 5  # <!*
    ps_scriptlet = 6  # <?
    ps_comment = 7  # <!--
    ps_script = 17
    ps_style = 22
    ps_will_close_comment1 = 8  # -
    ps_will_close_comment2 = 9  # --    -. at last comeback to prev state
    ps_tag_name = 10
    ps_wait_attr_or_close = 11
    ps_wait_eq_or_attr_or_close = 20    # attr[ ]
    ps_wait_value_or_attr_or_close = 21    # attr =[ ]
    ps_attr = 12
    ps_value = 13
    ps_tag_will_close = 14  # /
    ps_tag_enter_children = 15  # > 临时状态，压入堆栈并翻转为 ps_text
    ps_tag_exit_children = 17  # </
    ps_tag_exit_children_tag_name = 18  # </tag
    ps_tag_closed = 19  # /> </tag>  临时状态，弹出堆栈并翻转为堆栈前端状态
    ps_end_sub_state = 100       # 子状态结束
    

cdef enum StringState:
    vs_not_start = 4
    vs_double_quote = 1  # double quoted value
    vs_single_quote = 2  # single quoted value
    vs_escaping_dbl = 120
    vs_escaping_sng = 121
    vs_escaping_regexp = 122
    vs_no_quote = 5

cdef enum ScriptState:
    sc_code = 1
    sc_slash = 2            # /
    sc_line_comment = 3
    sc_multiline_comment = 4            # /*
    sc_multiline_comment_will_end = 5   # /* *
    sc_double_quote = 8
    sc_single_quote = 9
    sc_escaping_dbl = 14
    sc_escaping_sng = 13
    sc_slash_will_regexp = 11
    sc_regexp = 12  # 前一字符为 + - * / ; > | & < ? = % ^ [ ] { } () 时 / 有可能为正则表达式，为文本、数字则不可能
    sc_will_close_tag_lt = 30
    sc_will_close_tag_lt_slash = 31
    sc_will_close_tag_lt_slash_s = 32
    sc_will_close_tag_lt_slash_sc = 33
    sc_will_close_tag_lt_slash_scr = 34
    sc_will_close_tag_lt_slash_scri = 35
    sc_will_close_tag_lt_slash_scrip = 36
    sc_will_close_tag_lt_slash_script = 37

    sc_will_close_tag_lt_slash_st = 38
    sc_will_close_tag_lt_slash_sty = 39
    sc_will_close_tag_lt_slash_styl = 40
    sc_will_close_tag_lt_slash_style = 41

cdef MessageType get_msg_type(Py_UCS4 c) nogil:
    if c == u'<':
        return mt_lt
    elif c == u'/':
        return mt_slash
    elif c == u'"':
        return mt_double_quote
    elif c == u'>':
        return mt_gt
    elif c == u'=':
        return mt_eq
    elif c in [u' ', u'\t', u'\r', u'\n']:
        return mt_space
    elif c == u'\'':
        return mt_single_quote
    else:
        return mt_text

cdef int feed_string_literal(int sub_state, int mt, Py_UCS4 c) nogil:
    if sub_state == vs_double_quote:
        if mt == mt_text and c == u'\\':
            return vs_escaping_dbl
        elif mt == mt_double_quote:
            return ps_end_sub_state
    elif sub_state == vs_escaping_dbl:
        return vs_double_quote
    elif sub_state == vs_single_quote:
        if mt == mt_text and c == u'\\':
            return vs_escaping_sng
        elif mt == mt_single_quote:
            return ps_end_sub_state
    elif sub_state == vs_escaping_dbl:
        return vs_single_quote

    return sub_state


cdef void feed_script(int sub_state2, int mt, Py_UCS4 c, ParseResult * result) nogil:
    if c == u'*':
        mt = mt_star

    cdef int action = act_append
    cdef int new_sub_state2 = sub_state2

    if sub_state2 == sc_code:
        if c in [u'+', u'-', u'*', u';', u'>', u'|', u'&', u'<', u'?', u'=', u'%', u'^', u'[', u']',u'{', u'}', u'(']:
            result.maybe_regexp = 1
        elif mt != mt_space:        # 由于没有LA，无法处理 var a = /*xxx*//abcd/
            result.maybe_regexp = 0

        if mt == mt_slash:
            new_sub_state2 = sc_slash
        elif mt == mt_double_quote:
            new_sub_state2 = sc_double_quote
        elif mt == mt_single_quote:
            new_sub_state2 = sc_single_quote
        elif mt == mt_lt:
            new_sub_state2 = sc_will_close_tag_lt
            action = act_undetermine
    elif sub_state2 == sc_slash:
        if mt == mt_star:
            new_sub_state2 = sc_multiline_comment
        elif mt == mt_slash:
            new_sub_state2 = sc_line_comment
        elif result.maybe_regexp:
            new_sub_state2 = sc_regexp
            result.maybe_regexp = 0
        else:
            new_sub_state2 = sc_code
    elif sub_state2 == sc_multiline_comment:
        if mt == mt_star:
            new_sub_state2 = sc_multiline_comment_will_end
    elif sub_state2 == sc_multiline_comment_will_end:
        if mt == mt_slash:
            new_sub_state2 = sc_code        # else stay in comment
    elif sub_state2 == sc_line_comment:
        if mt == mt_space and (c == u'\n' or c == u'\r'):
            new_sub_state2 = sc_code
    elif sub_state2 == sc_regexp:
        if mt == mt_slash:
            new_sub_state2 = sc_code
        elif c == u'\\':
            new_sub_state2 = vs_escaping_regexp
    elif sub_state2 == vs_escaping_regexp:
        new_sub_state2 = sc_regexp

    elif sub_state2 == sc_double_quote:
        if c == u'\\':
            new_sub_state2 = vs_escaping_dbl
        elif c == u'"':
            new_sub_state2 = sc_code
    elif sub_state2 == sc_single_quote:
        if c == u'\\':
            new_sub_state2 = vs_escaping_sng
        elif c == u"'":
            new_sub_state2 = sc_code
    elif sub_state2 == vs_escaping_dbl:
        new_sub_state2 = sc_double_quote
    elif sub_state2 == vs_escaping_sng:
        new_sub_state2 = sc_single_quote

    elif sub_state2 == sc_will_close_tag_lt:
        if mt == mt_slash:
            new_sub_state2 = sc_will_close_tag_lt_slash
            action = act_undetermine
        else:
            not_script_close(result, mt, c)
            return

    elif sub_state2 == sc_will_close_tag_lt_slash:
        if c == u's':
            new_sub_state2 = sc_will_close_tag_lt_slash_s
            action = act_undetermine
        else:
            not_script_close(result, mt, c)
            return
    elif sub_state2 == sc_will_close_tag_lt_slash_s:
        if c == u'c':
            action = act_undetermine
            new_sub_state2 = sc_will_close_tag_lt_slash_sc
        else:
            not_script_close(result, mt, c)
            return
    elif sub_state2 == sc_will_close_tag_lt_slash_sc:
        if c == u'r':
            action = act_undetermine
            new_sub_state2 = sc_will_close_tag_lt_slash_scr
        else:
            not_script_close(result, mt, c)
            return
    elif sub_state2 == sc_will_close_tag_lt_slash_scr:
        if c == u'i':
            action = act_undetermine
            new_sub_state2 = sc_will_close_tag_lt_slash_scri
        else:
            not_script_close(result, mt, c)
            return
    elif sub_state2 == sc_will_close_tag_lt_slash_scri:
        if c == u'p':
            action = act_undetermine
            new_sub_state2 = sc_will_close_tag_lt_slash_scrip
        else:
            not_script_close(result, mt, c)
            return
    elif sub_state2 == sc_will_close_tag_lt_slash_scrip:
        if c == u't':
            action = act_undetermine
            new_sub_state2 = sc_will_close_tag_lt_slash_script
        else:
            not_script_close(result, mt, c)
            return
    elif sub_state2 == sc_will_close_tag_lt_slash_script:
        if mt == mt_gt:
            new_sub_state2 = 0
            action = act_pass | act_end
            result.state = ps_tag_closed
            result.changed = 1
        else:
            new_sub_state2 = sc_code
            action = act_resume | act_append

    result.sub2 = new_sub_state2
    result.action = action


cdef void feed_style(int sub_state2, int mt, Py_UCS4 c, ParseResult * result) nogil:
    if c == u'*':
        mt = mt_star

    cdef int action = act_append
    cdef int new_sub_state2 = sub_state2

    if sub_state2 == sc_code:
        if mt == mt_slash:
            new_sub_state2 = sc_slash
        elif mt == mt_double_quote:
            new_sub_state2 = sc_double_quote
        elif mt == mt_single_quote:
            new_sub_state2 = sc_single_quote
        elif mt == mt_lt:
            new_sub_state2 = sc_will_close_tag_lt
            action = act_undetermine
    elif sub_state2 == sc_slash:
        if mt == mt_star:
            new_sub_state2 = sc_multiline_comment
        # elif mt == mt_slash:      css 内没有行注释
        #     new_sub_state2 = sc_line_comment
        elif result.maybe_regexp:
            new_sub_state2 = sc_regexp
            result.maybe_regexp = 0
        else:
            new_sub_state2 = sc_code
    elif sub_state2 == sc_multiline_comment:
        if mt == mt_star:
            new_sub_state2 = sc_multiline_comment_will_end
    elif sub_state2 == sc_multiline_comment_will_end:
        if mt == mt_slash:
            new_sub_state2 = sc_code  # else stay in comment
    # elif sub_state2 == sc_line_comment:
    #     if mt == mt_space and (c == u'\n' or c == u'\r'):
    #         new_sub_state2 = sc_code

    elif sub_state2 == sc_double_quote:
        if c == u'\\':
            new_sub_state2 = vs_escaping_dbl
        elif c == u'"':
            new_sub_state2 = sc_code
    elif sub_state2 == sc_single_quote:
        if c == u'\\':
            new_sub_state2 = vs_escaping_sng
        elif c == u"'":
            new_sub_state2 = sc_code
    elif sub_state2 == vs_escaping_dbl:
        new_sub_state2 = sc_double_quote
    elif sub_state2 == vs_escaping_sng:
        new_sub_state2 = sc_single_quote

    elif sub_state2 == sc_will_close_tag_lt:
        if mt == mt_slash:
            new_sub_state2 = sc_will_close_tag_lt_slash
            action = act_undetermine
        else:
            not_style_close(result, mt, c)
            return

    elif sub_state2 == sc_will_close_tag_lt_slash:
        if c == u's':
            new_sub_state2 = sc_will_close_tag_lt_slash_s
            action = act_undetermine
        else:
            not_style_close(result, mt, c)
            return
    elif sub_state2 == sc_will_close_tag_lt_slash_s:
        if c == u't':
            action = act_undetermine
            new_sub_state2 = sc_will_close_tag_lt_slash_st
        else:
            not_style_close(result, mt, c)
            return
    elif sub_state2 == sc_will_close_tag_lt_slash_st:
        if c == u'y':
            action = act_undetermine
            new_sub_state2 = sc_will_close_tag_lt_slash_sty
        else:
            not_style_close(result, mt, c)
            return
    elif sub_state2 == sc_will_close_tag_lt_slash_sty:
        if c == u'l':
            action = act_undetermine
            new_sub_state2 = sc_will_close_tag_lt_slash_styl
        else:
            not_style_close(result, mt, c)
            return
    elif sub_state2 == sc_will_close_tag_lt_slash_styl:
        if c == u'e':
            action = act_undetermine
            new_sub_state2 = sc_will_close_tag_lt_slash_style
        else:
            not_style_close(result, mt, c)
            return
    elif sub_state2 == sc_will_close_tag_lt_slash_style:
        if mt == mt_gt:
            new_sub_state2 = 0
            action = act_pass | act_end
            result.state = ps_tag_closed
            result.changed = 1
        else:
            new_sub_state2 = sc_code
            action = act_resume | act_append

    result.sub2 = new_sub_state2
    result.action = action

cdef void not_script_close(ParseResult * result, int mt, Py_UCS4 c) nogil:
    feed_script(sc_code, mt, c, result)
    if result.action & act_undetermine:
        result.action = act_pass | act_undetermine
    else:
        result.action = act_resume

cdef void not_style_close(ParseResult * result, int mt, Py_UCS4 c) nogil:
    feed_script(sc_code, mt, c, result)
    if result.action & act_undetermine:
        result.action = act_pass | act_undetermine
    else:
        result.action = act_resume


cdef void feed_c(ParseState state, int sub_state, int sub_state2, Py_UCS4 c, ParseResult * result) nogil:
    # state 用于 ps_state，html 主要状态
    # sub_state 用于 tag 的字符串、注释、script 段、style 段等
    # sub_state2 用于 script 段及 style 段内的注释及字符串，也用于 ps_scriptlet
    cdef ParseState new_state = state
    cdef int new_sub_state = sub_state
    cdef int new_sub_state2 = sub_state2
    cdef int mt = get_msg_type(c)
    cdef int action = 0
    if state == ps_text:
        if sub_state == ps_script:
            feed_script(sub_state2, mt, c, result)
            return
        elif sub_state == ps_style:
            feed_style(sub_state2, mt, c, result)
            return

        if mt == mt_lt:     # <
            new_state = ps_will_tag
            action = act_undetermine
        else:
            action = act_append

    elif state == ps_will_tag:  # <
        if mt == mt_lt:
            action = act_resume | act_undetermine  # 之前的字符 < 视为 text，本字符 < undetermine
        elif mt == mt_text:
            if c == u'!':
                new_state = ps_will_dtd
                action = act_undetermine
            elif c == u'?':
                new_state = ps_tag_name
                action = act_pass | act_start
                new_sub_state2 = ps_scriptlet
            else:
                action = act_throw | act_start  # 之前的字符 < 抛弃，本字符开始新内容
                new_state = ps_tag_name

        elif mt == mt_slash:        # </
            action = act_undetermine
            new_state = ps_tag_exit_children

    elif state == ps_will_dtd:
        if mt == mt_text and c == u'-':
            action = act_undetermine
            new_state = ps_will_comment
        elif mt == mt_lt:
            action = act_resume | act_undetermine
            new_state = ps_will_tag
        elif mt == mt_gt:
            action = act_pass | act_end
            new_state = ps_text
        else:
            action = act_start
            new_state = ps_dtd

    elif state == ps_dtd:
        if mt == mt_gt:
            action = act_pass | act_end
            new_state = ps_tag_closed
        else:
            action = act_append

    elif state == ps_will_comment:
        if mt == mt_text and c == u'-':
            action = act_pass | act_start
            new_state = ps_comment
        elif mt == mt_lt:
            action = act_resume | act_undetermine
            new_state = ps_will_tag
        else:
            action = act_resume
            new_state = ps_text

    elif state == ps_comment:
        if mt == mt_text and c == u'-':
            action = act_undetermine
            new_state = ps_will_close_comment1
        else:
            action = act_append

    elif state == ps_will_close_comment1:
        if mt == mt_text and c == u'-':
            action = act_undetermine
            new_state = ps_will_close_comment2
        else:
            action = act_resume | act_append

    elif state == ps_will_close_comment2:
        if mt == mt_gt:
            action = act_pass | act_end
            new_state = ps_tag_closed
        elif mt == mt_text and c == u'-':
            action == act_undetermine   # TODO <!-- ---> 其中 "-"--> 的 "-" 应视为正常文本，但是 resume 只能 resume 所有 undetermine 故 ---> 全部视为注释结尾
        else:
            action = act_resume | act_append

    elif state == ps_tag_exit_children:
        if mt == mt_text:       # </t
            action = act_resume | act_throw | act_pass | act_start
            new_state = ps_tag_exit_children_tag_name
        else:
            action = act_resume
            new_state = ps_text

    elif state == ps_tag_exit_children_tag_name:
        if mt == mt_gt:         # </tag>
            action = act_pass | act_end
            new_state = ps_tag_closed
        elif mt == mt_space:
            action = act_pass
        elif mt == mt_text:     # </tag
            action = act_append
        else:
            action = act_error

    elif state == ps_tag_name:  # <tag a
        if mt == mt_space:      # <tag a[ ]
            action = act_pass | act_end
            new_state = ps_wait_attr_or_close
        elif sub_state2 == 0 and mt == mt_slash:    # <tag/
            action = act_pass | act_end
            new_state = ps_tag_will_close
        elif sub_state2 == ps_scriptlet and mt == mt_text and c == u'?':
            action = act_pass | act_end
            new_state = ps_tag_will_close
        elif mt == mt_gt:       # <tag>
            action = act_pass | act_end
            new_state = ps_tag_enter_children
        else:
            action = act_append
    
    elif state == ps_wait_attr_or_close:    # <tag[ ]
        if mt == mt_text:
            if sub_state2 == ps_scriptlet and c == u'?':
                action = act_undetermine
                new_state = ps_tag_will_close
            else:
                new_state = ps_attr
                action = act_start
        elif mt == mt_gt:
            new_state = ps_tag_enter_children
            action = act_pass | act_end
        elif mt == mt_slash:    # <tag /
            action = act_undetermine
            new_state = ps_tag_will_close

    elif state == ps_wait_eq_or_attr_or_close:  # <tag attr[ ]
        if mt == mt_text:       # <tag attr a
            if sub_state2 == ps_scriptlet and c == u'?':
                action = act_undetermine
                new_state = ps_tag_will_close
            else:
                new_state = ps_attr
                action = act_start

        elif mt == mt_space:    # <tag attr[ ][ ]
            action = act_pass
        elif mt == mt_eq:       # <tag attr =
            action = act_end | act_pass
            new_state = ps_value
            new_sub_state = vs_not_start
        elif mt == mt_gt:       # <tag attr >
            new_state = ps_tag_enter_children
            action = act_pass | act_end
        elif sub_state2 == 0 and mt == mt_slash:   # <tag attr /
            action = act_undetermine
            new_state = ps_tag_will_close

    elif state == ps_attr:      # <tag attr
        if mt == mt_space:      # <tag attr[ ]
            action = act_end | act_pass
            new_state = ps_wait_eq_or_attr_or_close
        elif sub_state2 == 0 and mt == mt_slash:    # <tag attr/
            action = act_undetermine
            new_state = ps_tag_will_close
        elif sub_state2 == ps_scriptlet and mt == mt_text and c == u'?':
            action = act_pass | act_end
            new_state = ps_tag_will_close
        elif mt == mt_gt:       # <tag attr>
            action = act_end | act_pass
            new_state = ps_tag_enter_children
        elif mt == mt_eq:       # <tag attr=
            action = act_end | act_pass
            new_state = ps_value
            new_sub_state = vs_not_start
        else:                   # <tag attribute
            action = act_append

    elif state == ps_value:     # <tag attr=
        if sub_state == vs_not_start:
            if mt == mt_space:     # <tag attr=[ ]
                action = act_pass
                new_sub_state = vs_not_start
            elif mt == mt_double_quote:       # <tag attr="
                action = act_pass | act_start
                new_sub_state = vs_double_quote
            elif mt == mt_single_quote:     # <tag attr='
                action = act_pass | act_start
                new_sub_state = vs_single_quote
            elif mt == mt_gt:
                pass
            else:
                action = act_start          # <tag attr=v
                new_sub_state = vs_no_quote
        elif sub_state in [vs_double_quote, vs_single_quote]:  # <tag attr="
            new_sub_state = feed_string_literal(sub_state, mt, c)
            if new_sub_state == ps_end_sub_state:   # <tag attr="v"
                new_sub_state = 0
                new_state = ps_wait_attr_or_close
                action = act_end | act_pass
            elif new_sub_state in [vs_escaping_dbl, vs_escaping_sng]:      # <tag attr="v\
                action = act_pass
            else:                                   # <tag attr="value
                action = act_append
        else: # no_quote
            if mt == mt_space:      # <tag attr=v[]
                new_state = ps_wait_attr_or_close
                action = act_end | act_pass
            elif mt == mt_gt:
                new_state = ps_tag_enter_children
                action = act_end | act_pass
            elif sub_state2 == 0 and mt == mt_slash:
                action = act_undetermine
                new_state = ps_tag_will_close
            elif sub_state2 == ps_scriptlet and mt == mt_text and c == u'?':
                action = act_undetermine
                new_state = ps_tag_will_close
            else:                   # <tag attr=value
                action = act_append

    elif state == ps_tag_will_close:   # <tag... /
        if mt == mt_gt:         # <tag... />
            action = act_throw | act_end
            new_state = ps_tag_closed
        else:                   # <tag a=/ b=
            action = act_resume | act_reject

    if new_state != state:
        result.changed = 1
    else:
        result.changed = 0

    result.action = action
    result.state = new_state
    result.sub = new_sub_state
    result.sub2 = new_sub_state2


class Selector(object):
    def __init__(self, tag: str = None, id:str = None, classes = [], appear_times = 0, total_times = 0):
        self.attrs = []  # 需要关注的属性
        self.patterns = dict()  # {attr: expect value}
        self.classes = []
        self._child = None
        self._descendant = None
        self.cond_count = 0  # 条件个数

        self.tag = tag
        if tag :
            self.cond_count += 1
        if id:
            self.attr('id', value=id)
        self.classes = set(classes)
        if classes:
            self.attr('class', '<placeholder>')
        self.appear_times = appear_times
        self.total_times = total_times

    def attr(self, attr: str, value: str = None):
        self.cond_count += 1
        self.patterns[attr] = value
        if not attr in self.attrs:
            self.attrs.append(attr)
        return self

    def child(self, selector):
        self._child = selector
        return self

    def descendant(self, selector):
        self._descendant = selector
        return self

    def test_tag(self, tag: str):
        return self.tag is None or self.tag == tag


    def test_attr(self, attr:str, value:str):
        if attr not in self.patterns: return None

        if attr == 'class':
            if value:
                _class = set(value.split(' '))
                return self.classes.issubset(_class)
        else:
            p = self.patterns[attr]
            if p is None:
                return True
            else:
                return p == value


    # div#content:1 #container #meta > #title-wrapper > h3 > #video-title
    def compile(self, rule_str: str):
        #TODO
        pass

    def __repr__(self):
        s = ''
        if self.tag: s += self.tag
        for attr in self.patterns:
            if attr == 'id':
                s += '#' + self.patterns[attr]
            elif attr != 'class':
                s += '[' + attr
                if self.patterns[attr]:
                    s += '=' + self.patterns[attr]
                s += ']'
        for c in self.classes:
            s += '.' + c

        if self._child:
            s += ' > ' + self._child.__repr__()
        if self._descendant:
            s += ' ' + self._descendant.__repr__()

        return s

class Scanner(object):

    def __init__(self, selector, extract_attr, debug = False):
        self.debug = debug

        self.selector = selector
        self.matched_value = None
        self.matched = 0        # 0 unknown  1 - full matched -1 tag impossible -2 node full impossible
        self.matched_count = 0
        self.prev_depth = 0
        self.stack = []     # (depth, selector)
        extract_attr = extract_attr.lower()
        self.extract_attr = extract_attr
        self.scan_inner_text = (self.extract_attr == 'innertext')
        self.scan_inner_html = (self.extract_attr == 'innerhtml')
        self.is_final = self.selector._child is None or self.selector._descendant is None
        self.expected_depth = 0
        self.parser = None
        self.curr_depth = 0

        self.total_appear_times = dict()      # id(selector) -> int times
        self.appear_times = dict()
        s = selector
        while True:
            self.total_appear_times[id(s)] = 0
            self.appear_times[id(s)] = 0
            s = s._child or s._descendant
            if s is None: break

        self.collect_inner_text = 0
        self.inner_text = io.StringIO()
        self.is_paragraph = False

        self.is_complete = False

    def start_tag(self, tag: str, depth):
        if self.collect_inner_text:
            self.is_paragraph = not (tag in ['span', 'b', 'i', 'font', 'tr', 'table'])
            if self.is_paragraph: self.inner_text.write('\n')

        self.matched = 0
        self.matched_count = 0
        self.curr_depth = depth

        if self.debug: print('%s start_tag %s, curr selector %s' % ('\t' * depth, tag, self.selector))
        if self.collect_inner_text: return

        if self.selector.test_tag(tag):
            self.matched_count += 1
            if self.matched_count >= self.selector.cond_count:
                self.matched = 1
        else:
            self.matched = -1

        if self.debug: print('%s matched %s' % ('\t' * depth, self.matched))

        if depth == self.expected_depth:
            if (self.is_final and not self.scan_inner_text) or (self.matched == -1 and self.stack):
                if self.debug: print('%s until close %s since tag mismatch' % ('\t' * depth, depth))
                self.parser.until_close_depth = depth

    def attr(self, attr:str, value:str):
        depth = self.curr_depth
        if self.debug: print('%s attr %s = %s' % ('\t' * self.curr_depth, attr, value))

        if self.matched == -1: return

        if self.is_final and self.extract_attr == attr:
            if self.scan_inner_html or self.scan_inner_text:
                self.onfound(value)
                if self.selector.total_times and self.total_appear_times[id(self.selector)] >= self.selector.total_times:
                    self.is_complete = True

                if self.selector.appear_times and self.appear_times[id(self.selector)] >= self.selector.appear_times:
                    self.parser.until_close_depth = depth - 1
                    if self.debug: print('%s until close %s since exceed appear times limit' % ('\t' * depth, depth - 1))
            else:
                self.matched_value = value

        if self.matched == 0:
            t = self.selector.test_attr(attr, value)
            if t is None:
                pass
            elif t:
                self.matched_count += 1
                if self.matched_count >= self.selector.cond_count:
                    self.matched = 1
                    if self.debug: print('matched = 1')
            else: # false
                self.matched = -1
                if self.debug: print('matched = -1')
                if self.is_final and self.is_child:
                    self.parser.until_close_depth = self.curr_depth
                    if self.debug: print('%s until close %s since is final and attr mismatch' % ('\t' * depth, self.curr_depth))

        if depth == self.expected_depth:
            if (self.is_final and not self.scan_inner_text) or (self.matched == -1 and self.stack):
                if self.debug: print('%s until close %s since ...' % ('\t' * depth, depth))
                self.parser.until_close_depth = depth


    def close_tag_without_children(self, depth):
        if self.collect_inner_text:
            if self.is_paragraph: self.inner_text.write('\n')
            if self.collect_inner_text == depth:
                self.attr('innertext', self.inner_text.getvalue())
                self.collect_inner_text = 0

        if self.debug: print('%s close_tag_without_children' % ('\t' * depth))

        if self.collect_inner_text: return

        if self.matched == 1 and self.is_final:
            self.total_appear_times[id(self.selector)] += 1
            self.appear_times[id(self.selector)] += 1
            self.onfound(self.matched_value)
            if (self.selector.total_times and self.total_appear_times[id(self.selector)] >= self.selector.total_times):
                self.is_complete = True
            if self.selector.appear_times and self.appear_times[id(self.selector)] >= self.selector.appear_times:
                self.parser.until_close_depth = self.curr_depth - 1
                if self.debug: print('%s until close %s' % ('\t' * depth, self.curr_depth -1))


    def close_tag(self, depth):

        if self.collect_inner_text:
            if self.is_paragraph:
                self.inner_text.write('\n')

            if self.collect_inner_text == depth:
                self.attr('innertext', self.inner_text.getvalue())
                self.inner_text.truncate(0)
                self.inner_text.seek(0)
                self.collect_inner_text = 0


        if self.debug: print('%s close_tag' % ('\t' * depth))
        if self.collect_inner_text: return
        if self.prev_depth == depth:
            if self.stack:
                self.prev_depth, self.selector = self.stack.pop()
                self.is_final = False
                self.is_child = False
                if self.selector._child:
                    self.appear_times[id(self.selector._child)] = 0;
                elif self.selector._descendant:
                    self.appear_times[id(self.selector._descendant)] = 0;
                #('%s pop stack, selector = %s, is final = %s' % ('\t' * depth, self.selector, self.is_final))


    def enter_children(self, depth):
        if depth == self.expected_depth:
            if (self.is_final and not self.scan_inner_text) or (self.matched == -1 and self.stack):
                if self.debug: print('%s until close %s' % ('\t' * depth, depth))
                self.parser.until_close_depth = depth
                if self.debug: print('%s until close %s' % ('\t' * depth, depth))

        if self.debug: print('%s enter_children' % ('\t' * depth))

        if self.matched == 1:
            self.total_appear_times[id(self.selector)] += 1
            self.appear_times[id(self.selector)] += 1

            next = self.selector._child
            if next:
                self.expected_depth = depth + 1
            else:
                next = self.selector._descendant
                if next:
                    self.expected_depth = 0

            if self.debug: print('%s expected depth %s' % ('\t' * depth, self.expected_depth))

            if next is None:
                if self.scan_inner_html:
                    self.parser.collect_inner_html = depth
                elif self.scan_inner_text:
                    self.collect_inner_text = depth
                else:
                    self.onfound(self.matched_value)
                    if (self.selector.total_times and self.total_appear_times[id(self.selector)] >= self.selector.total_times):
                        self.is_complete = True
                    if self.selector.appear_times and self.appear_times[id(self.selector)] >= self.selector.appear_times:
                        self.parser.until_close_depth = self.curr_depth - 1
                        if self.debug: print('%s until close %s' % ('\t' * depth, self.curr_depth - 1))
            else:
                self.stack.append((self.prev_depth, self.selector))
                self.is_child = self.selector._child is not None
                self.selector = next
                self.prev_depth = depth
                self.is_final = self.selector._child is None and self.selector._descendant is None
                # print('%s push stack, selector=%s, is final = %s' % ('\t' * depth, self.selector, self.is_final))


    def text(self, s:str):
        if self.collect_inner_text:
            self.inner_text.write(s.strip())

class Parser(object):
    def __init__(self, scanner: Scanner):
        cdef ParseResult result = ParseResult()
        result.state = 0
        result.sub = 0
        result.sub2 = 0
        result.action = 0
        result.changed = 0
        result.maybe_regexp = 0

        self.result = result

        self.state = ps_text
        self.sub_state = 0
        self.sub_state2 = 0
        self.state_before_undetermine = 0

        self.span = io.StringIO()
        self.undetermine = io.StringIO()

        self.curr_tag = None
        self.attrs = []
        self.curr_attr = None
        self.curr_attr_value = None
        # self.stack = []
        self.curr_depth = 0

        self.scanner = scanner
        scanner.parser = self
        self.until_close_depth = 0
        self.collect_inner_html = 0
        self.inner_html = io.StringIO()
        self.last_lt_slash = 0

    def feed(self, unicode s):
        if self.scanner.is_complete:
            return

        cdef ParseResult result
        result = self.result
        for c in s:
            if self.collect_inner_html:
                if c == u'<':
                    self.last_lt_slash = self.inner_html.tell()
                self.inner_html.write(c)


            result.state = self.state
            result.sub = self.sub_state
            result.sub2 = self.sub_state2
            result.action = 0
            result.changed = 0

            feed_c(self.state, self.sub_state, self.sub_state2, c, &result)

            old_state = self.state
            if result.action & act_reject :
                self.state = self.state_before_undetermine
            else:
                self.state = result.state
            self.sub_state = result.sub
            self.sub_state2 = result.sub2
            # print('\t\t%s state: %2s sub_state: %s sub2: %s action: %2s span: %s undetermine: %s' % (c, self.state, self.sub_state, self.sub_state2, result.action, self.span.getvalue(), self.undetermine.getvalue()))

            if result.action & act_undetermine:
                self.state_before_undetermine = old_state
                if not result.action & act_pass:
                    self.undetermine.write(c)

            if result.action & act_throw:
                self.undetermine.truncate(0)
                self.undetermine.seek(0)

            if result.action & act_resume:
                if not result.action & act_pass:
                    self.undetermine.write(c)
                self.span.write(self.undetermine.getvalue())
                self.undetermine.truncate(0)
                self.undetermine.seek(0)

            if result.action == act_append:
                self.span.write(c)

            if result.action & act_start:
                self.end_curr(old_state, result.changed)
                self.undetermine.truncate(0)
                self.undetermine.seek(0)
                self.span.truncate(0)
                self.span.seek(0)
                if not result.action & act_pass:
                    self.span.write(c)

            if result.action & act_end:
                if not result.action & act_pass:
                    self.span.write(c)
                self.end_curr(old_state, result.changed)
                self.undetermine.truncate(0)
                self.undetermine.seek(0)
                self.span.truncate(0)
                self.span.seek(0)

            if self.scanner.is_complete:
                print('no more match needed')
                return

    def clear(self):
        self.state = ps_text
        self.sub_state = 0
        self.sub_state2 = 0
        self.curr_tag = None
        self.attrs = []
        self.curr_attr = None
        self.curr_attr_value = None

    def end_curr(self, int old_state, int changed):
        new_state = self.state

        if self.span.tell() and changed:
            if old_state == ps_text:
                # print('text %2s' % (self.span.getvalue()))
                if self.until_close_depth and self.curr_depth > self.until_close_depth:
                    pass
                else:
                    self.scanner.text(self.span.getvalue())
            elif old_state in [ps_will_tag, ps_tag_exit_children]:
                # print('text %2s' % (self.span.getvalue()))
                if self.until_close_depth and self.curr_depth > self.until_close_depth:
                    pass
                else:
                    self.scanner.text(self.span.getvalue())
            elif old_state == ps_tag_name:
                self.curr_tag = self.span.getvalue()
                #print('begin tag %s' % self.curr_tag)
                self.curr_depth += 1
                if self.until_close_depth and self.curr_depth > self.until_close_depth:
                    pass
                else:
                    self.scanner.start_tag(self.curr_tag, self.curr_depth)

            elif old_state == ps_value:
                if self.until_close_depth and self.curr_depth > self.until_close_depth:
                    pass
                else:
                    self.curr_attr_value = self.span.getvalue()

            elif old_state == ps_attr:
                if self.until_close_depth and self.curr_depth > self.until_close_depth:
                    pass
                else:
                    if self.curr_attr:
                        self.attrs.append((self.curr_attr, self.curr_attr_value))
                        self.scanner.attr(self.curr_attr, self.curr_attr_value)

                    self.curr_attr = self.span.getvalue().lower()
                    self.curr_attr_value = None

        if new_state == ps_tag_enter_children:
            #print('enter children')
            if self.curr_attr:
                if self.until_close_depth and self.curr_depth > self.until_close_depth:
                    pass
                else:
                    self.attrs.append((self.curr_attr, self.curr_attr_value))
                    self.scanner.attr(self.curr_attr, self.curr_attr_value)

            if self.curr_tag in ['input','img','meta','br']:
                #print('close tag %s' % self.span.getvalue())
                if self.until_close_depth and self.curr_depth > self.until_close_depth:
                    pass
                else:
                    self.scanner.close_tag_without_children(self.curr_depth)
                    if self.until_close_depth and self.curr_depth == self.until_close_depth:
                        self.until_close_depth = 0
                self.curr_depth -= 1
                self.clear()
            elif self.curr_tag == 'script':
                self.state = ps_text
                self.sub_state = ps_script
                self.sub_state2 = sc_code
            elif self.curr_tag == 'style':
                self.state = ps_text
                self.sub_state = ps_style
                self.sub_state2 = sc_code
            else:
                if self.until_close_depth and self.curr_depth > self.until_close_depth:
                    pass
                else:
                    self.scanner.enter_children(self.curr_depth)

                self.state = ps_text
                # self.stack.append((self.state, self.sub_state, self.curr_tag, self.attrs))
                self.clear()
                #print('stack %s' % (self.stack))

        if new_state == ps_comment:
            #print('start comment')
            pass

        elif new_state == ps_dtd:
            #print('start dtd')
            pass

        elif new_state == ps_tag_closed:
            if old_state == ps_tag_exit_children_tag_name:
                #print('close tag have children')
                if self.collect_inner_html and self.curr_depth == self.collect_inner_html:
                    self.collect_inner_html = 0
                    self.inner_html.truncate(self.last_lt_slash)
                    self.scanner.attr('innerhtml', self.inner_html.getvalue())
                    self.inner_html.truncate(0)
                    self.inner_html.seek(0)

                if self.until_close_depth and self.curr_depth > self.until_close_depth:
                    pass
                else:
                    if self.until_close_depth and self.curr_depth == self.until_close_depth:
                        self.until_close_depth = 0
                    self.scanner.close_tag(self.curr_depth)
                self.curr_depth -= 1
                # state, sub_state, curr_tag, attrs = self.stack.pop()
            elif old_state == ps_will_close_comment2:
                self.state = ps_text
                #print('end comment %s' % self.span.getvalue())
                return;
            elif old_state == ps_dtd:
                self.state = ps_text
                #print('end dtd %s' % self.span.getvalue())
                return;
            else:
                #print('close tag %s without children' % self.span.getvalue())
                if self.until_close_depth and self.curr_depth > self.until_close_depth:
                    pass
                else:
                    if self.collect_inner_html and self.curr_depth == self.collect_inner_html:
                        self.collect_inner_html = 0
                        self.scanner.attr('innerhtml', '')
                        self.inner_html.truncate(0)
                        self.inner_html.seek(0)

                    if self.until_close_depth and self.curr_depth == self.until_close_depth:
                        self.until_close_depth = 0
                    self.scanner.close_tag_without_children(self.curr_depth)
                    self.curr_depth -= 1
            self.clear()
