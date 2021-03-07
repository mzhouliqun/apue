#include <stdio.h>
#define VAL

int main(void)
{

#ifdef VAL
		printf("%d\n", (int)VAL);
#endif
		return 0;
}

