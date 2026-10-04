初次 EqualRoot 只有 SEL/long double 时，原版 KVC hash 无可用字段，会退回对象地址。这是混杂因素；为比较 SEL/long double 是否参与 equality，加入双方相同的 NSString anchor 后重新运行。没有修改库实现或既有验收断言。
