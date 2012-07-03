/**
	Utiltiy functions for array processing

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.utils.array;

void removeFromArray(T)(ref T[] array, T item)
{
	foreach( i; 0 .. array.length )
		if( array[i] is item ){
			removeFromArrayIdx(array, i);
			return;
		}
}

void removeFromArrayIdx(T)(ref T[] array, size_t idx)
{
	foreach( j; idx+1 .. array.length)
		array[j-1] = array[j];
	array.length = array.length-1;
}

/*struct SparseAppender(T : E[], E)
{
	static struct Entry {
		Entry* prev;
		T data;
	}

	private {
		size_t m_length = 0;
		Entry* m_entries;
		E[] m_buf;
		size_t m_bufFill = 0;
	}

	void put(T arr)
	{
		if( m_bufFill.length > 0 ){
			
		}
		Entry e;
		e.prev = m_entries;
		e.data = arr;
		m_entries = e;
		m_length += arr.length;
	}

	void put(E itm)
	{
		if( m_bufFill >= m_buf.length ) put(null);

		m_buf[m_bufFill++] = itm;
	}

	private void merge()
	{
		if( m_
	}
}*/
