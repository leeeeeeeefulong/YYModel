"""Exact integer oracle, independent of Foundation/Double/Decimal conversion."""
import re
import random

DECIMAL = re.compile(r'([+-]?)([0-9]*)(?:\.([0-9]*))?(?:[eE]([+-]?[0-9]+))?\Z')
HEX = re.compile(r'([+-]?)0[xX]([0-9a-fA-F]*)(?:\.([0-9a-fA-F]*))?[pP]([+-]?[0-9]+)\Z')
LIMITS = {'Int64': (-(1 << 63), (1 << 63)-1), 'UInt64': (0, (1 << 64)-1),
          'Int8': (-128, 127), 'UInt8': (0, 255)}

def integer_value(text):
    text = text.strip()
    m = HEX.fullmatch(text)
    if m:
        sign, whole, fraction, exponent = m.groups()
        fraction = fraction or ''
        if not whole and not fraction: return None
        coefficient = int((whole+fraction) or '0', 16)
        scale = int(exponent)-4*len(fraction)
        if coefficient == 0: result = 0
        elif scale > 128: result = 1 << 256
        elif scale < -coefficient.bit_length(): result = 0
        elif scale >= 0: result = coefficient << scale
        else: result = coefficient >> -scale
    else:
        m = DECIMAL.fullmatch(text)
        if not m: return None
        sign, whole, fraction, exponent = m.groups()
        fraction = fraction or ''
        if not whole and not fraction: return None
        coefficient = int((whole+fraction) or '0')
        scale = int(exponent or '0')-len(fraction)
        if coefficient == 0: result = 0
        elif scale > 100: result = 10**200
        elif scale < -len(str(coefficient)): result = 0
        elif scale >= 0: result = coefficient*10**scale
        else: result = coefficient//10**-scale
    return -result if sign == '-' else result

def cases():
    result = []
    def add(label, target, text, decimal_expected=None):
        if target == 'Decimal': expected = decimal_expected
        else:
            v = integer_value(text)
            lo, hi = LIMITS[target]
            expected = str(v) if v is not None and lo <= v <= hi else None
        result.append(dict(label=label,target=target,text=text,expected=expected))
    explicit = [
        ('zero-padded-negative-exponent','123e-000001'),
        ('zero-padded-negative-zero-exponent','1e-000000'),
        ('range-with-zero-padded-exponent','9223372036854775808e-000000'),
        ('range-with-zero-padded-exponent','-9223372036854775809e-000000'),
        ('zero-huge-exponent','0e+999999'),
        ('tiny-exponent','1e-129'),('tiny-exponent','-1e-400'),
        ('hex-precision','0x20000000000001p0'),
        ('hex-range','-0x8000000000000001p0'),
        ('hex-unsigned-max','0xffffffffffffffffp0'),
        ('unicode-digit-cluster','1\u0301e0'),
        ('unicode-digit-cluster','1\ufe0fe0'),
        ('exact-decimal-coefficient','1'+'0'*160+'e-160'),
        ('exact-decimal-coefficient','9'*160+'e-159'),
        ('huge-positive-exponent','1e+999999'),
        ('long-zero-exponent','123e-'+('0'*100)+'1'),
        ('hex-fraction-truncation','0x1.fffffffffffffp-1'),
        ('hex-fraction-truncation','-0x1.8p0'),
        ('hex-precision-fraction','0x20000000000001.8p0'),
        ('hex-long-coefficient','0x1'+'0'*100+'p-400'),
        ('hex-long-coefficient','0x'+('f'*100)+'p-396'),
        ('hex-tiny-exponent','0x1p-999999'),
        ('hex-zero-exponent','-0x0p+999999'),
    ]
    malformed = ['123abc','1.8xyz','1e2garbage','1e','e1','1e++1','--1','1.2.3','1e1.2','0x1p','0x1p1junk','１.0','١.0','1\u0301e0','1\ufe0fe0']
    for target in LIMITS:
        for label,text in explicit: add(label,target,text)
        for text in malformed: add('invalid-syntax',target,text)
        lo,hi=LIMITS[target]
        for n in [lo-1,lo,lo+1,hi-1,hi,hi+1,0,1,-1,9007199254740993]:
            for suffix in ['', '.0','.9','e0','e-000000','e-00000','e+000000']:
                add('integer-boundary',target,str(n)+suffix)
        for n in range(-20,21):
            for zeros in [0,4,5,6,8]:
                add('exponent-zero-padding',target,f'{n}e-{"0"*zeros}1')
        rng=random.Random(1729)
        for _ in range(120):
            coefficient=rng.randrange(-10**22,10**22)
            exponent=rng.randrange(-30,7)
            add('seeded-decimal-exponent',target,f'{coefficient}e{exponent:+d}')
        for n in [0,1,127,128,255,256,(1<<53)-1,(1<<53)+1,(1<<63)-1,(1<<63)+1,(1<<64)-1]:
            for sign in ['', '-']: add('hex-boundary',target,f'{sign}0x{n:x}p0')
    for text in malformed + ['1\u0301','1\ufe0f']:
        add('decimal-invalid-syntax','Decimal',text)
    for text,expected in [('1.8','1.8'),('-1.8','-1.8'),('9007199254740993.0','9007199254740993'),('0x1p4','16'),('0x20000000000001p0','9007199254740993'),('0x1.8p-1','0.75'),('-0x1.8p0','-1.5'),('0xffffffffffffffffp0','18446744073709551615'),('0x1'+('0'*100)+'p-400','1'),('0e+999999','0'),('123e-'+('0'*100)+'1','12.3')]:
        add('decimal-value','Decimal',text,expected)
    for target in ['Int64','UInt64']:
        for text in ['9007199254740993','9223372036854775807','18446744073709551615']:
            add('exact-NSDecimalNumber',target,text)
            result[-1]['kind']='nsDecimal'
        for text in ['9223372036854775807.0','18446744073709551615.0','-9223372036854775809.0']:
            add('exact-JSON-NSDecimalNumber',target,text)
            result[-1]['kind']='jsonNumber'
    # One assertion per unique target, input channel, and input text.
    unique={}
    for item in result:
        unique.setdefault((item['target'],item.get('kind','string'),item['text']),item)
    return list(unique.values())
