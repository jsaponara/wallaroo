#!/usr/bin/env python3

"""
Market Trade FIX Symbol router

"""

from .fix_parse import parse_fix


FUNC_NAME = 'Fixrouter'


def func(input):
    return (hash(parse_fix(input).get('Symbol', 0)), input)


# TESTS #
def test_fixrouter():
    input = ('8=FIX.4.2\x019=64\x0135=S\x0155=TSLA\x01'
             '60=20151204-14:30:00.000\x01117=S\x01132=16.40\x01133=16.60'
             '\x0110=098\x01')
    assert(func(input) == (-8085089165823708899, input))
