export type NumberStyle = 'number' | 'tokens' | 'money' | 'rate'

const integer = {}
const compact = { notation: 'compact', maximumSignificantDigits: 3 } as const
const dollars = { style: 'currency', currency: 'USD', minimumFractionDigits: 2, maximumFractionDigits: 2 } as const
const smallDollars = { ...dollars, maximumFractionDigits: 6 }
const rate = { style: 'percent', minimumFractionDigits: 1, maximumFractionDigits: 1 } as const

export function numberOptions(style: NumberStyle, value: number) {
  switch (style) {
    case 'tokens': return value < 10000 ? integer : compact
    case 'money': return value > 0 && value < 0.01 ? smallDollars : dollars
    case 'rate': return rate
    default: return integer
  }
}
